import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private let detector = ChordDetector()
    private let overlay = SelectionOverlayController()
    private let capturer = ScreenCapturer()
    private let launchAgent = LaunchAgentController()
    private var permissionTimer: Timer?
    private var didAskForPermissions = false
    private var lastPermissionState: (screen: Bool, accessibility: Bool)?

    private var isDemoMode: Bool { CommandLine.arguments.contains("--demo") }

    /// Debug modes that must not block on the permission dialog.
    private var isSilentMode: Bool {
        isDemoMode || CommandLine.arguments.contains("--coord-test")
    }

    // MARK: - Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        if activateRunningInstance() {
            NSApp.terminate(nil)
            return
        }

        setupStatusItem()

        detector.onChord = { [weak self] in self?.beginSelection() }
        detector.start()

        overlay.onFinish = { [weak self] result in self?.handle(result) }

        permissionTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            self?.refreshPermissions()
        }
        refreshPermissions()

        if isDemoMode {
            scheduleDemo()
        }

        if CommandLine.arguments.contains("--coord-test") {
            runCoordinateTest()
        }

        if CommandLine.arguments.contains("--request-permissions") {
            Log.d("Requesting the permissions from the command line")
            Permissions.requestScreenRecording()
            Permissions.requestAccessibility()
        }

        Log.d("ScreenTap started")
    }

    func applicationWillTerminate(_ notification: Notification) {
        detector.stop()
        permissionTimer?.invalidate()
    }

    /// Makes sure only one instance is running (the login item may start a second one).
    private func activateRunningInstance() -> Bool {
        guard let bundleID = Bundle.main.bundleIdentifier else { return false }
        let current = NSRunningApplication.current
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .filter { $0 != current }
        guard let other = others.first else { return false }
        other.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
        return true
    }

    // MARK: - Status item

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(systemSymbolName: "camera.viewfinder", accessibilityDescription: "ScreenTap")
        statusItem.button?.image?.isTemplate = true
        statusItem.button?.toolTip = "ScreenTap — press both mouse buttons to capture an area"
        statusItem.menu = buildMenu()

        // The menu bar lays the item out asynchronously, so report its final frame
        // a moment later.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            Log.d("Status item window frame (settled): \(self?.statusItem.button?.window?.frame ?? .zero)")
        }
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self

        let select = NSMenuItem(title: "Select Screen Area…", action: #selector(manualSelection), keyEquivalent: "")
        select.target = self
        menu.addItem(select)

        menu.addItem(.separator())

        let login = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        login.target = self
        login.state = launchAgent.isEnabled ? .on : .off
        menu.addItem(login)

        menu.addItem(.separator())

        let requestScreen = NSMenuItem(title: "Request Screen Recording Permission", action: #selector(requestScreenRecording), keyEquivalent: "")
        requestScreen.target = self
        menu.addItem(requestScreen)

        let requestAccessibility = NSMenuItem(title: "Request Accessibility Permission", action: #selector(requestAccessibility), keyEquivalent: "")
        requestAccessibility.target = self
        menu.addItem(requestAccessibility)

        let settings = NSMenuItem(title: "Open Privacy Settings…", action: #selector(openScreenRecordingSettings), keyEquivalent: "")
        settings.target = self
        menu.addItem(settings)

        menu.addItem(.separator())

        let about = NSMenuItem(title: "About ScreenTap", action: #selector(showAbout), keyEquivalent: "")
        about.target = self
        menu.addItem(about)

        // macOS applies permission changes to a running app only partially, so a
        // restart makes a freshly granted permission take effect right away.
        let restart = NSMenuItem(title: "Restart ScreenTap", action: #selector(restartApp), keyEquivalent: "r")
        restart.target = self
        menu.addItem(restart)

        let quit = NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        return menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        refreshPermissions()
    }

    private func refreshPermissions() {
        let screenOK = Permissions.screenRecordingGranted
        let accessibilityOK = Permissions.accessibilityGranted

        // macOS does not hand a freshly granted permission to a running process
        // completely, so restart as soon as one of them arrives.
        if let previous = lastPermissionState {
            if (!previous.screen && screenOK) || (!previous.accessibility && accessibilityOK) {
                Log.d("A permission was granted — restarting ScreenTap")
                lastPermissionState = (screenOK, accessibilityOK)
                restartApp()
                return
            }
        }
        lastPermissionState = (screenOK, accessibilityOK)

        detector.refreshSource()

        // "camera.viewfinder.badge.exclamationmark" does not exist in SF Symbols,
        // so the warning state uses a plain triangle.
        let symbol = (screenOK && accessibilityOK) ? "camera.viewfinder" : "exclamationmark.triangle.fill"
        if let image = NSImage(systemSymbolName: symbol, accessibilityDescription: "ScreenTap") {
            image.isTemplate = true
            statusItem.button?.image = image
            Log.d("Status item symbol \"\(symbol)\", size \(image.size), screen recording: \(screenOK), accessibility: \(accessibilityOK)")
            Log.d("Status item window frame: \(statusItem.button?.window?.frame ?? .zero)")
        } else {
            Log.e("SF Symbol \"\(symbol)\" is not available")
        }

        if !screenOK {
            statusItem.button?.toolTip = "ScreenTap — the “Screen Recording” permission is required"
        } else if !accessibilityOK {
            statusItem.button?.toolTip = "ScreenTap — without Accessibility the context menu will pop up"
        } else {
            statusItem.button?.toolTip = "ScreenTap — press both mouse buttons to capture an area"
        }

        if !didAskForPermissions && (!screenOK || !accessibilityOK) && !isSilentMode {
            didAskForPermissions = true
            // No modal dialog here: a blocking alert at launch would stall the
            // whole app and swallow the permission request. The warning triangle
            // in the menu bar plus the system prompt on the first gesture is
            // enough of a hint.
            Log.d("Permissions missing: screen recording \(screenOK), accessibility \(accessibilityOK)")
        }
    }

    // MARK: - Actions

    @objc private func manualSelection() {
        beginSelection()
    }

    @objc private func toggleLaunchAtLogin() {
        if launchAgent.isEnabled {
            launchAgent.disable()
        } else {
            let executable = Bundle.main.executablePath ?? CommandLine.arguments.first ?? ""
            do {
                try launchAgent.enable(executablePath: executable)
            } catch {
                Log.e("Could not enable launch at login: \(error.localizedDescription)")
                presentError(title: "Could not enable launch at login", message: error.localizedDescription)
            }
        }
    }

    @objc private func openScreenRecordingSettings() {
        Permissions.openScreenRecordingSettings()
    }

    @objc private func requestScreenRecording() {
        Permissions.requestScreenRecording()
    }

    @objc private func requestAccessibility() {
        Permissions.requestAccessibility()
    }

    @objc private func openAccessibilitySettings() {
        Permissions.openAccessibilitySettings()
    }

    @objc private func showAbout() {
        let alert = NSAlert()
        alert.messageText = "ScreenTap \(version)"
        alert.informativeText = """
        Press both mouse buttons at the same time to open the area selection mode.
        The captured region is copied to the clipboard right away.

        Selection: drag with the mouse. Enter confirms, Esc cancels.
        A click without dragging selects the whole screen.
        """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    /// Relaunches the app so that permission changes take effect immediately.
    @objc private func restartApp() {
        let bundleURL = Bundle.main.bundleURL.path
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", "sleep 1; open '\(bundleURL)' >/dev/null 2>&1 &"]
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        do {
            try task.run()
        } catch {
            Log.e("Could not relaunch the app: \(error.localizedDescription)")
        }
        NSApp.terminate(nil)
    }

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
    }

    // MARK: - Selection flow

    private func beginSelection() {
        guard !overlay.isActive else { return }

        // The first use is the natural moment to ask for the screen recording
        // permission: macOS binds the grant to the running binary, which is
        // exactly what we need, and the app restarts itself once it arrives.
        if !Permissions.screenRecordingGranted {
            Log.d("No screen recording permission yet — asking macOS")
            Permissions.requestScreenRecording()
        }

        detector.isSuspended = true
        overlay.begin()
    }

    private func handle(_ result: SelectionResult) {
        detector.isSuspended = false
        switch result {
        case .cancelled:
            break
        case .selected(let rect):
            capture(rect)
        }
    }

    private func capture(_ rect: CGRect) {
        // The overlay is already hidden — wait a moment so that it does not end up
        // in the captured frame.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            guard let self else { return }
            Task {
                do {
                    let image = try await self.capturer.capture(region: rect)
                    if self.isDemoMode {
                        ClipboardWriter.write(image, alsoSaveTo: "/tmp/screentap-demo.png")
                        Log.d("DEMO: screenshot saved to /tmp/screentap-demo.png (\(image.width)×\(image.height))")
                    } else {
                        ClipboardWriter.write(image)
                    }
                    FeedbackSound.playSuccess()
                } catch {
                    Log.e("Capture failed: \(error.localizedDescription)")
                    FeedbackSound.playFailure()
                    // Ask macOS right away so the grant is bound to this binary.
                    if case CaptureError.screenRecordingDenied = error {
                        Permissions.requestScreenRecording()
                    }
                    self.presentError(title: "Could not take the screenshot", message: error.localizedDescription)
                }
            }
        }
    }

    private func presentError(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    // MARK: - Demo

    /// Captures the top right corner of the screen (the menu bar clock) and writes
    /// it to a file. Used to verify the coordinate conversion of the capture.
    private func runCoordinateTest() {
        guard let screen = NSScreen.screens.first else { return }
        let region = CGRect(
            x: screen.frame.width - 420,
            y: screen.frame.maxY - 70,
            width: 420,
            height: 70
        )
        Task {
            do {
                let image = try await capturer.capture(region: region)
                let rep = NSBitmapImageRep(cgImage: image)
                guard let png = rep.representation(using: .png, properties: [:]) else { return }
                let path = "/tmp/screentap/coordtest.png"
                try png.write(to: URL(fileURLWithPath: path))
                Log.d("COORD TEST: region \(region) → \(image.width)×\(image.height) saved to \(path)")
            } catch {
                Log.e("COORD TEST failed: \(error.localizedDescription)")
            }
        }
    }

    private func scheduleDemo() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            guard let self, let screen = NSScreen.main ?? NSScreen.screens.first else { return }
            let size = NSSize(width: 800, height: 500)
            let rect = CGRect(
                x: screen.frame.midX - size.width / 2,
                y: screen.frame.midY - size.height / 2,
                width: size.width,
                height: size.height
            )
            Log.d("DEMO: running a scripted selection")
            self.overlay.begin(presetGlobalRect: rect, autoConfirm: 0.8)
        }
    }
}
