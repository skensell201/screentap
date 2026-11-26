import AppKit

/// Result of the interactive region selection.
enum SelectionResult {
    case selected(CGRect)   // global Cocoa coordinates (origin bottom-left)
    case cancelled
}

/// Full-screen overlay that lets the user drag a rectangle on top of the desktop.
final class SelectionOverlayController {
    /// Called when the selection is finished (selected or cancelled).
    var onFinish: ((SelectionResult) -> Void)?

    private var window: OverlayWindow?
    private var view: OverlayView?

    var isActive: Bool { window != nil }

    /// Starts the selection.
    /// - Parameters:
    ///   - presetGlobalRect: pre-filled rectangle in global Cocoa coordinates (used by the demo mode).
    ///   - autoConfirm: automatically confirm after the given delay instead of waiting for the user.
    func begin(presetGlobalRect: CGRect? = nil, autoConfirm: TimeInterval? = nil) {
        guard window == nil else { return }

        let screens = NSScreen.screens
        guard !screens.isEmpty else {
            onFinish?(.cancelled)
            return
        }

        let frame = screens.map(\.frame).reduce(CGRect.null) { $0.union($1) }

        let window = OverlayWindow(
            contentRect: frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.overlayWindow)))
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        window.isMovableByWindowBackground = false
        window.animationBehavior = .none

        let view = OverlayView(frame: CGRect(origin: .zero, size: frame.size))
        view.autoresizingMask = [.width, .height]
        window.contentView = view

        view.onFinish = { [weak self] result in
            self?.finish(result)
        }

        self.window = window
        self.view = view

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        window.makeFirstResponder(view)

        if let presetGlobalRect {
            view.applyPreset(presetGlobalRect, in: frame)
        }
        if let autoConfirm {
            DispatchQueue.main.asyncAfter(deadline: .now() + autoConfirm) { [weak self] in
                guard let self, self.isActive else { return }
                self.view?.confirmCurrentSelection()
            }
        }

        Log.d("Selection overlay shown")
    }

    /// Hides the overlay without selecting anything.
    func cancel() {
        finish(.cancelled)
    }

    private func finish(_ result: SelectionResult) {
        guard let window else { return }
        self.window = nil
        self.view = nil
        window.orderOut(nil)
        Log.d("Overlay closed: \(result)")
        onFinish?(result)
    }
}

/// Borderless window that is allowed to take keyboard focus.
private final class OverlayWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// The view that draws the dimmed desktop, the selection rectangle and the HUD.
private final class OverlayView: NSView {
    var onFinish: ((SelectionResult) -> Void)?

    private var selection: CGRect?
    private var dragStart: CGPoint = .zero
    private var isDragging = false
    private var cursorLocation: CGPoint = .zero
    private var trackingArea: NSTrackingArea?

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }

        let bounds = self.bounds
        context.setFillColor(NSColor.black.withAlphaComponent(0.35).cgColor)

        if let selection, selection.width > 1, selection.height > 1 {
            // Dim everything around the selection.
            let top = CGRect(x: 0, y: 0, width: bounds.width, height: selection.minY)
            let bottom = CGRect(x: 0, y: selection.maxY, width: bounds.width, height: bounds.height - selection.maxY)
            let left = CGRect(x: 0, y: selection.minY, width: selection.minX, height: selection.height)
            let right = CGRect(x: selection.maxX, y: selection.minY, width: bounds.width - selection.maxX, height: selection.height)
            for rect in [top, bottom, left, right] where !rect.isEmpty {
                context.fill(rect)
            }

            drawSelectionBorder(selection)
            drawSizeHUD(for: selection)
        } else {
            context.fill(bounds)
            drawCrosshair()
        }
    }

    private func drawSelectionBorder(_ rect: CGRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        let accent = NSColor.controlAccentColor

        context.setStrokeColor(accent.withAlphaComponent(0.95).cgColor)
        context.setLineWidth(2)
        context.stroke(rect.insetBy(dx: 1, dy: 1))

        // Corner handles.
        context.setFillColor(accent.cgColor)
        let handle: CGFloat = 4
        for point in [
            CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY),
            CGPoint(x: rect.minX, y: rect.maxY), CGPoint(x: rect.maxX, y: rect.maxY),
        ] {
            context.fillEllipse(in: CGRect(x: point.x - handle, y: point.y - handle, width: handle * 2, height: handle * 2))
        }
    }

    private func drawCrosshair() {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.setStrokeColor(NSColor.white.withAlphaComponent(0.7).cgColor)
        context.setLineWidth(1)
        context.move(to: CGPoint(x: cursorLocation.x, y: 0))
        context.addLine(to: CGPoint(x: cursorLocation.x, y: bounds.height))
        context.move(to: CGPoint(x: 0, y: cursorLocation.y))
        context.addLine(to: CGPoint(x: bounds.width, y: cursorLocation.y))
        context.strokePath()
    }

    private func drawSizeHUD(for rect: CGRect) {
        let text = "\(Int(rect.width.rounded())) × \(Int(rect.height.rounded()))"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .medium),
            .foregroundColor: NSColor.white,
        ]
        let attributed = NSAttributedString(string: text, attributes: attributes)
        let textSize = attributed.size()

        let padding: CGFloat = 8
        let boxSize = CGSize(width: textSize.width + padding * 2, height: textSize.height + padding)
        var boxOrigin = CGPoint(x: rect.minX, y: rect.maxY + 8)
        if boxOrigin.y + boxSize.height > bounds.height {
            boxOrigin.y = rect.minY - boxSize.height - 8
        }
        if boxOrigin.y < 0 { boxOrigin.y = rect.minY + 8 }
        if boxOrigin.x + boxSize.width > bounds.width {
            boxOrigin.x = bounds.width - boxSize.width - 8
        }
        if boxOrigin.x < 0 { boxOrigin.x = 8 }

        let box = CGRect(origin: boxOrigin, size: boxSize)
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.setFillColor(NSColor.black.withAlphaComponent(0.65).cgColor)
        let path = CGPath(roundedRect: box, cornerWidth: 6, cornerHeight: 6, transform: nil)
        context.addPath(path)
        context.fillPath()

        attributed.draw(at: CGPoint(x: box.origin.x + padding, y: box.origin.y + padding / 2))
    }

    // MARK: - Mouse

    override func mouseDown(with event: NSEvent) {
        let point = clampToBounds(convert(event.locationInWindow, from: nil))
        dragStart = point
        isDragging = true
        selection = CGRect(origin: point, size: .zero)
        setNeedsDisplay(bounds)
    }

    override func mouseDragged(with event: NSEvent) {
        guard isDragging else { return }
        let point = clampToBounds(convert(event.locationInWindow, from: nil))
        selection = CGRect(
            x: min(dragStart.x, point.x),
            y: min(dragStart.y, point.y),
            width: abs(point.x - dragStart.x),
            height: abs(point.y - dragStart.y)
        )
        setNeedsDisplay(bounds)
    }

    override func mouseUp(with event: NSEvent) {
        guard isDragging else { return }
        isDragging = false

        guard let selection else { return }
        if selection.width < 4 || selection.height < 4 {
            // A click without a drag selects the whole screen under the cursor.
            let point = convert(event.locationInWindow, from: nil)
            let globalPoint = globalPoint(for: point)
            if let screen = NSScreen.screens.first(where: { NSPointInRect(globalPoint, $0.frame) }) {
                onFinish?(.selected(screen.frame))
            } else {
                onFinish?(.cancelled)
            }
            return
        }
        onFinish?(.selected(globalRect(for: selection)))
    }

    override func mouseMoved(with event: NSEvent) {
        cursorLocation = convert(event.locationInWindow, from: nil)
        if selection == nil { setNeedsDisplay(bounds) }
    }

    // MARK: - Keyboard

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 53: // Escape
            onFinish?(.cancelled)
        case 36, 76, 49: // Return, Space, keypad Enter
            confirmCurrentSelection()
        default:
            super.keyDown(with: event)
        }
    }

    func confirmCurrentSelection() {
        guard let selection, selection.width >= 4, selection.height >= 4 else {
            onFinish?(.cancelled)
            return
        }
        onFinish?(.selected(globalRect(for: selection)))
    }

    // MARK: - Helpers

    /// Fills the selection with a preset rectangle given in global Cocoa coordinates.
    func applyPreset(_ globalRect: CGRect, in windowFrame: CGRect) {
        let local = CGRect(
            x: globalRect.minX - windowFrame.minX,
            y: windowFrame.maxY - globalRect.maxY,
            width: globalRect.width,
            height: globalRect.height
        )
        selection = local
        setNeedsDisplay(bounds)
    }

    private func globalRect(for viewRect: CGRect) -> CGRect {
        guard let window else { return viewRect }
        let origin = window.frame.origin
        return CGRect(
            x: origin.x + viewRect.origin.x,
            y: origin.y + window.frame.height - viewRect.origin.y - viewRect.height,
            width: viewRect.width,
            height: viewRect.height
        )
    }

    /// Converts a point of the (flipped) view into global Cocoa coordinates.
    private func globalPoint(for viewPoint: CGPoint) -> CGPoint {
        guard let window else { return viewPoint }
        return CGPoint(
            x: window.frame.origin.x + viewPoint.x,
            y: window.frame.origin.y + window.frame.height - viewPoint.y
        )
    }

    private func clampToBounds(_ point: CGPoint) -> CGPoint {
        CGPoint(
            x: min(max(point.x, 0), bounds.width),
            y: min(max(point.y, 0), bounds.height)
        )
    }
}
