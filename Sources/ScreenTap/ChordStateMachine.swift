import CoreGraphics

/// The three groups of mouse buttons we distinguish.
enum MouseButton: String, Hashable {
    case left
    case right
    case other
}

/// What the caller should do with the event that produced this directive.
enum ChordDirective: Equatable {
    /// Deliver the event to the rest of the system unchanged.
    case pass
    /// Swallow the event.
    case swallow
    /// Swallow the event; the chord is armed and all following button events are swallowed too.
    case armChord
    /// Re-inject the buffered right-button press, then deliver the current event.
    case repostBufferedDown
    /// Swallow the event; the chord is complete.
    case chordCompleted
}

/// Pure state machine that turns a stream of mouse button events into
/// "both main buttons were pressed" decisions.
///
/// It knows nothing about AppKit or CGEvent, which makes it directly testable
/// (see `SelfTest`).
///
/// Two gestures are recognised:
///
/// * **overlap** — the second button goes down while the first one is still held
///   and no more than `window` seconds have passed since the first press;
/// * **sequence** — the first button was a quick click (without pointer travel)
///   and the second button goes down within `window` seconds of that click.
///
/// Right-button presses are always swallowed and buffered. If no chord materialises
/// the press is re-injected, which keeps the context menu working — only ~`window`
/// seconds later.
struct ChordStateMachine {
    /// Maximum delay between the two button presses.
    var window: CFTimeInterval = 0.20
    /// Pointer travel above this value marks the first press as a drag.
    var dragThreshold: CGFloat = 10

    private enum RightPress {
        case none
        /// Swallowed, waiting to be re-injected or to become a chord.
        case buffered
        /// Already re-injected, can no longer start a chord.
        case expired
    }

    private var leftPressedAt: CFTimeInterval?
    private var leftReleasedAt: CFTimeInterval?
    private var leftPressLocation: CGPoint = .zero
    private var leftWasDrag = false
    private var leftIsDown = false

    private var rightPressedAt: CFTimeInterval?
    private var rightIsDown = false
    private var rightPress: RightPress = .none

    private var armed = false
    private var chordButtons: Set<MouseButton> = []

    var isArmed: Bool { armed }
    var hasBufferedRightPress: Bool { rightPress == .buffered }

    // MARK: - Input

    mutating func buttonDown(_ button: MouseButton, at time: CFTimeInterval, location: CGPoint) -> ChordDirective {
        switch button {
        case .left:
            guard !armed else { return .swallow }
            leftIsDown = true
            leftPressedAt = time
            leftPressLocation = location
            leftReleasedAt = nil
            leftWasDrag = false
            // The right button is already held (and still fresh) → the chord starts here.
            if rightIsDown, rightPress == .buffered, let pressed = rightPressedAt, time - pressed <= window {
                return armChord(trigger: .left)
            }
            return .pass

        case .right:
            guard !armed else { return .swallow }
            rightIsDown = true
            rightPressedAt = time
            // The left button is already held → chord (but only if it is fresh enough).
            if leftIsDown, let pressed = leftPressedAt, time - pressed <= window {
                return armChord(trigger: .right)
            }
            // The left button was clicked (not dragged) shortly before → chord.
            if let pressed = leftPressedAt, let released = leftReleasedAt,
               !leftWasDrag, time - pressed <= window {
                return armChord(trigger: .right)
            }
            // Not a chord (yet): swallow the press and keep it buffered so that it
            // can be re-injected later without the context menu showing up.
            rightPress = .buffered
            return .swallow

        case .other:
            return .pass
        }
    }

    mutating func buttonUp(_ button: MouseButton, at time: CFTimeInterval, location: CGPoint) -> ChordDirective {
        switch button {
        case .left:
            leftIsDown = false
            guard armed else {
                leftReleasedAt = time
                leftWasDrag = distance(from: leftPressLocation, to: location) > dragThreshold
                return .pass
            }
            chordButtons.remove(.left)
            return finishIfComplete()

        case .right:
            rightIsDown = false
            guard armed else {
                if rightPress == .buffered {
                    // The press was swallowed; re-inject it so that it stays in
                    // front of this release.
                    rightPress = .expired
                    resetLeftPress()
                    return .repostBufferedDown
                }
                rightPress = .none
                return .pass
            }
            chordButtons.remove(.right)
            return finishIfComplete()

        case .other:
            return .pass
        }
    }

    /// Called periodically so that a buffered right-button press is re-injected
    /// even when the button is held down for a long time.
    mutating func tick(now: CFTimeInterval) -> ChordDirective {
        guard rightPress == .buffered, let pressed = rightPressedAt, now - pressed > window else { return .pass }
        rightPress = .expired
        resetLeftPress()
        return .repostBufferedDown
    }

    /// Full reset, e.g. after the chord has been handled.
    mutating func reset() {
        leftPressedAt = nil
        leftReleasedAt = nil
        leftPressLocation = .zero
        leftWasDrag = false
        leftIsDown = false
        rightPressedAt = nil
        rightIsDown = false
        rightPress = .none
        armed = false
        chordButtons.removeAll()
    }

    // MARK: - Private

    private mutating func armChord(trigger: MouseButton) -> ChordDirective {
        armed = true
        chordButtons.removeAll()
        if leftIsDown { chordButtons.insert(.left) }
        if rightIsDown { chordButtons.insert(.right) }
        chordButtons.insert(trigger)
        rightPress = .none
        return .armChord
    }

    private mutating func finishIfComplete() -> ChordDirective {
        guard chordButtons.isEmpty else { return .swallow }
        reset()
        return .chordCompleted
    }

    private mutating func resetLeftPress() {
        leftPressedAt = nil
        leftReleasedAt = nil
        leftWasDrag = false
    }

    private func distance(from a: CGPoint, to b: CGPoint) -> CGFloat {
        hypot(a.x - b.x, a.y - b.y)
    }
}
