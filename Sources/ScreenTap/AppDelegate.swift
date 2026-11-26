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

        Log.d("ScreenTap запущен")
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
        statusItem.button?.toolTip = "ScreenTap — двойное нажатие обеими кнопками мыши"
        statusItem.menu = buildMenu()
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self

        let select = NSMenuItem(title: "Выделить область на экране", action: #selector(manualSelection), keyEquivalent: "")
        select.target = self
        menu.addItem(select)

        menu.addItem(.separator())

        let login = NSMenuItem(title: "Запускать при входе", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        login.target = self
        login.state = launchAgent.isEnabled ? .on : .off
        menu.addItem(login)

        menu.addItem(.separator())

        let screen = NSMenuItem(title: "Разрешение «Запись экрана»…", action: #selector(openScreenRecordingSettings), keyEquivalent: "")
        screen.target = self
        menu.addItem(screen)

        let accessibility = NSMenuItem(title: "Разрешение «Универсальный доступ»…", action: #selector(openAccessibilitySettings), keyEquivalent: "")
        accessibility.target = self
        menu.addItem(accessibility)

        menu.addItem(.separator())

        let about = NSMenuItem(title: "О ScreenTap", action: #selector(showAbout), keyEquivalent: "")
        about.target = self
        menu.addItem(about)

        let quit = NSMenuItem(title: "Выход", action: #selector(quit), keyEquivalent: "q")
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

        let symbol = (screenOK && accessibilityOK) ? "camera.viewfinder" : "camera.viewfinder.badge.exclamationmark"
        if let image = NSImage(systemSymbolName: symbol, accessibilityDescription: "ScreenTap") {
            image.isTemplate = true
            statusItem.button?.image = image
        }

        if !screenOK {
            statusItem.button?.toolTip = "ScreenTap — требуется разрешение «Запись экрана»"
        } else if !accessibilityOK {
            statusItem.button?.toolTip = "ScreenTap — без «Универсального доступа» будет мешать контекстное меню"
        } else {
            statusItem.button?.toolTip = "ScreenTap — двойное нажатие обеими кнопками мыши"
        }

        if !didAskForPermissions && (!screenOK || !accessibilityOK) && !isDemoMode {
            didAskForPermissions = true
            presentPermissionHint(screenOK: screenOK, accessibilityOK: accessibilityOK)
        }
    }

    private func presentPermissionHint(screenOK: Bool, accessibilityOK: Bool) {
        let alert = NSAlert()
        alert.messageText = "ScreenTap почти готов к работе"

        var lines: [String] = []
        if !screenOK {
            lines.append("""
            • «Запись экрана» — без неё снимок экрана сделать невозможно.
              Система спросит об этом сама при первом снимке, либо включите вручную:
              «Системные настройки → Конфиденциальность и безопасность → Запись экрана».
            """)
        }
        if !accessibilityOK {
            lines.append("""
            • «Универсальный доступ» — чтобы перехватывать нажатия обеих кнопок и
              не показывать контекстное меню приложения под курсором.
              «Системные настройки → Конфиденциальность и безопасность → Универсальный доступ».
            """)
        }

        alert.informativeText = lines.joined(separator: "\n")
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Открыть настройки")
        alert.addButton(withTitle: "Позже")

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
                Log.e("Не удалось включить автозапуск: \(error.localizedDescription)")
                presentError(title: "Не удалось включить автозапуск", message: error.localizedDescription)
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
        Нажмите одновременно обе основные кнопки мыши — появится режим выделения области.
        Выделенный фрагмент автоматически попадёт в буфер обмена.

        Выделение: протяните мышь. Enter — подтвердить, Esc — отменить.
        Клик без перетаскивания выделяет весь экран.
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
                        Log.d("DEMO: снимок сохранён в /tmp/screentap-demo.png (\(image.width)×\(image.height))")
                    } else {
                        ClipboardWriter.write(image)
                    }
                    FeedbackSound.playSuccess()
                } catch {
                    Log.e("Ошибка захвата: \(error.localizedDescription)")
                    FeedbackSound.playFailure()
                    self.presentError(title: "Не удалось сделать снимок", message: error.localizedDescription)
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
            Log.d("DEMO: программный прогон выделения")
            self.overlay.begin(presetGlobalRect: rect, autoConfirm: 0.8)
        }
    }
}
