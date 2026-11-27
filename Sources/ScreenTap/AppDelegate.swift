import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private let detector = ChordDetector()
    private let overlay = SelectionOverlayController()
    private let capturer = ScreenCapturer()
    private let launchAgent = LaunchAgentController()
    private var permissionTimer: Timer?
    private var didAskForPermissions = false

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

        let screen = NSMenuItem(title: "Screen Recording Permission…", action: #selector(openScreenRecordingSettings), keyEquivalent: "")
        screen.target = self
        menu.addItem(screen)

        let accessibility = NSMenuItem(title: "Accessibility Permission…", action: #selector(openAccessibilitySettings), keyEquivalent: "")
        accessibility.target = self
        menu.addItem(accessibility)

        menu.addItem(.separator())

        let about = NSMenuItem(title: "About ScreenTap", action: #selector(showAbout), keyEquivalent: "")
        about.target = self
        menu.addItem(about)

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

        detector.refreshSource()

        // "camera.viewfinder.badge.exclamationmark" does not exist in SF Symbols,
        // so the warning state uses a plain triangle.
        let symbol = (screenOK && accessibilityOK) ? "camera.viewfinder" : "exclamationmark.triangle.fill"
        if let image = NSImage(systemSymbolName: symbol, accessibilityDescription: "ScreenTap") {
            image.isTemplate = true
            statusItem.button?.image = image
            Log.d("Status item symbol \"\(symbol)\", size \(image.size), screen recording: \(screenOK), accessibility: \(accessibilityOK)")
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
            presentPermissionHint(screenOK: screenOK, accessibilityOK: accessibilityOK)
        }
    }

    private func presentPermissionHint(screenOK: Bool, accessibilityOK: Bool) {
        let alert = NSAlert()
        alert.messageText = "ScreenTap is almost ready"

        var lines: [String] = []
        if !screenOK {
            lines.append("""
            • “Screen Recording” is required to capture the screen contents.
              macOS asks for it the first time a screenshot is taken; you can also
              enable it manually in
              “System Settings → Privacy & Security → Screen Recording”.
            """)
        }
        if !accessibilityOK {
            lines.append("""
            • “Accessibility” lets ScreenTap intercept the presses of both mouse
              buttons without letting the context menu of the app under the cursor
              appear. Enable it in
              “System Settings → Privacy & Security → Accessibility”.
            """)
        }

        alert.informativeText = lines.joined(separator: "\n")
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Open Settings")
        alert.addButton(withTitle: "Later")

        // The app may have been started in the background (login item), so bring
        // the dialog to the front before showing it.
        NSApp.activate(ignoringOtherApps: true)

        if alert.runModal() == .alertFirstButtonReturn {
            if !screenOK { Permissions.openScreenRecordingSettings() }
            if !accessibilityOK { Permissions.openAccessibilitySettings() }
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

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
    }

    // MARK: - Selection flow

    private func beginSelection() {
        guard !overlay.isActive else { return }
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
