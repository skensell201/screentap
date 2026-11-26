import AppKit
import CoreGraphics

/// Detects the "both mouse buttons" gesture.
///
/// The primary source is a `CGEventTap`: it can swallow events, which keeps the
/// context menu of the application under the cursor from showing up. It needs the
/// "Accessibility" permission.
///
/// Without that permission the detector falls back to `NSEvent` global/local
/// monitors. They still detect the gesture, but they cannot suppress anything.
final class ChordDetector {
    enum Source: String {
        case eventTap
        case eventMonitor
        case none
    }

    /// Called on the main thread when the gesture was recognised.
    var onChord: (() -> Void)?

    /// While suspended every event is passed through untouched.
    var isSuspended = false

    private(set) var source: Source = .none

    private var machine = ChordStateMachine()
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var tickTimer: Timer?
    private var bufferedRightEvent: CGEvent?

    /// Magic value used to recognise events that we re-injected ourselves.
    private static let repostMarker: Int64 = 0x5343_5441  // "SCTA"

    private static weak var current: ChordDetector?

    // MARK: - Lifecycle

    func start() {
        ChordDetector.current = self
        startTickTimer()
        refreshSource()
    }

    func stop() {
        tickTimer?.invalidate()
        tickTimer = nil
        removeTap()
        removeMonitors()
        source = .none
    }

    /// Re-evaluates which event source can be used (permissions may change at
    /// any moment) and switches over if needed.
    func refreshSource() {
        if Permissions.accessibilityGranted {
            if source != .eventTap {
                removeMonitors()
                installTap()
            }
        } else {
            if source != .eventMonitor {
                removeTap()
                installMonitors()
            }
        }
    }

    // MARK: - CGEventTap

    private func installTap() {
        let mask = CGEventMask(
            (1 << CGEventType.leftMouseDown.rawValue)
            | (1 << CGEventType.leftMouseUp.rawValue)
            | (1 << CGEventType.rightMouseDown.rawValue)
            | (1 << CGEventType.rightMouseUp.rawValue)
        )

        let callback: CGEventTapCallBack = { _, type, event, _ in
            guard let detector = ChordDetector.current else {
                return Unmanaged.passUnretained(event)
            }
            return detector.handleTapEvent(type: type, event: event)
        }

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: callback,
            userInfo: nil
        ) else {
            Log.e("Не удалось создать CGEventTap — переключаюсь на мониторы событий")
            installMonitors()
            return
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        self.tap = tap
        self.runLoopSource = source
        self.source = .eventTap
        Log.d("Источник событий: CGEventTap")
    }

    private func removeTap() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        tap = nil
        runLoopSource = nil
        bufferedRightEvent = nil
    }

    private func handleTapEvent(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // Events we re-injected ourselves must not be processed again.
        if event.getIntegerValueField(.eventSourceUserData) == ChordDetector.repostMarker {
            return Unmanaged.passUnretained(event)
        }

        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            Log.d("Тап был отключён системой — включаю обратно")
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }

        guard !isSuspended else { return Unmanaged.passUnretained(event) }

        let now = CACurrentMediaTime()
        let location = event.location
        let directive: ChordDirective

        switch type {
        case .leftMouseDown:
            directive = machine.buttonDown(.left, at: now, location: location)
        case .rightMouseDown:
            directive = machine.buttonDown(.right, at: now, location: location)
            if directive == .swallow {
                // Keep a copy so that the press can be re-injected if no chord happens.
                rememberRightPress(event)
            }
        case .leftMouseUp:
            directive = machine.buttonUp(.left, at: now, location: location)
        case .rightMouseUp:
            directive = machine.buttonUp(.right, at: now, location: location)
        default:
            return Unmanaged.passUnretained(event)
        }

        return apply(directive, to: event)
    }

    // MARK: - NSEvent monitors (fallback)

    private func installMonitors() {
        let mask: NSEvent.EventTypeMask = [
            .leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp,
        ]

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] event in
            self?.handleMonitorEvent(event)
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            self?.handleMonitorEvent(event)
            return event
        }

        source = .eventMonitor
        Log.d("Источник событий: NSEvent monitors (без подавления контекстного меню)")
    }

    private func removeMonitors() {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        globalMonitor = nil
        localMonitor = nil
    }

    private func handleMonitorEvent(_ event: NSEvent) {
        Log.d("Событие монитора: \(event.type.rawValue)")
        guard !isSuspended else { return }
        let now = CACurrentMediaTime()
        let location = event.locationInWindow
        let button: MouseButton
        let directive: ChordDirective

        switch event.type {
        case .leftMouseDown:
            button = .left
            directive = machine.buttonDown(button, at: now, location: location)
        case .rightMouseDown:
            button = .right
            directive = machine.buttonDown(button, at: now, location: location)
        case .leftMouseUp:
            button = .left
            directive = machine.buttonUp(button, at: now, location: location)
        case .rightMouseUp:
            button = .right
            directive = machine.buttonUp(button, at: now, location: location)
        default:
            return
        }

        switch directive {
        case .chordCompleted:
            Log.d("Жест распознан")
            onChord?()
        default:
            break
        }
    }

    // MARK: - Shared handling

    private func apply(_ directive: ChordDirective, to event: CGEvent) -> Unmanaged<CGEvent>? {
        switch directive {
        case .pass:
            return Unmanaged.passUnretained(event)

        case .swallow:
            return nil

        case .armChord:
            Log.d("Жест: обе кнопки нажаты")
            bufferedRightEvent = nil
            return nil

        case .repostBufferedDown:
            reinsertBufferedRightPress()
            return Unmanaged.passUnretained(event)

        case .chordCompleted:
            Log.d("Жест: обе кнопки отпущены")
            bufferedRightEvent = nil
            DispatchQueue.main.async { [weak self] in
                self?.onChord?()
            }
            return nil
        }
    }

    private func reinsertBufferedRightPress() {
        guard let event = bufferedRightEvent else { return }
        bufferedRightEvent = nil
        event.setIntegerValueField(.eventSourceUserData, value: ChordDetector.repostMarker)
        event.timestamp = mach_absolute_time()
        event.post(tap: .cghidEventTap)
        Log.d("Правый клик возвращён в систему")
    }

    private func startTickTimer() {
        let timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
            guard let self else { return }
            let directive = self.machine.tick(now: CACurrentMediaTime())
            if directive == .repostBufferedDown {
                self.reinsertBufferedRightPress()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        tickTimer = timer
    }

    // MARK: - Buffering of right presses

    /// Keeps a copy of the swallowed right-button press so that it can be
    /// re-injected later.
    func rememberRightPress(_ event: CGEvent) {
        bufferedRightEvent = event.copy()
    }
}
