import CoreGraphics

/// Runs the `ChordStateMachine` against synthetic event sequences.
/// Executed with `ScreenTap --selftest`.
enum SelfTest {
    static func run() -> Int32 {
        var failures = 0

        func check(_ name: String, _ actual: ChordDirective?, _ expected: ChordDirective?) {
            let ok = actual == expected
            if !ok {
                failures += 1
                print("✗ \(name): expected \(expected.map { "\($0)" } ?? "nil"), got \(actual.map { "\($0)" } ?? "nil")")
            } else {
                print("✓ \(name)")
            }
        }

        let origin = CGPoint(x: 100, y: 100)
        let moved = CGPoint(x: 400, y: 300)

        // 1. A plain left click.
        do {
            var m = ChordStateMachine()
            check("plain left click (down)", m.buttonDown(.left, at: 0, location: origin), .pass)
            check("plain left click (up)", m.buttonUp(.left, at: 0.05, location: origin), .pass)
        }

        // 2. A plain right click: the press is swallowed and handed back.
        do {
            var m = ChordStateMachine()
            check("right click (down is swallowed)", m.buttonDown(.right, at: 0, location: origin), .swallow)
            check("right click (up hands the press back)", m.buttonUp(.right, at: 0.05, location: origin), .repostBufferedDown)
        }

        // 3. A held right click: the press is handed back by the timer.
        do {
            var m = ChordStateMachine()
            check("right click (down is swallowed)", m.buttonDown(.right, at: 0, location: origin), .swallow)
            check("right click (timer hands the press back)", m.tick(now: 0.30), .repostBufferedDown)
        }

        // 4. The gesture, left button first.
        do {
            var m = ChordStateMachine()
            check("chord, left first: left down", m.buttonDown(.left, at: 0, location: origin), .pass)
            check("chord, left first: right down", m.buttonDown(.right, at: 0.05, location: origin), .armChord)
            check("chord, left first: left up", m.buttonUp(.left, at: 0.10, location: origin), .swallow)
            check("chord, left first: right up", m.buttonUp(.right, at: 0.15, location: origin), .chordCompleted)
        }

        // 5. The gesture, right button first.
        do {
            var m = ChordStateMachine()
            check("chord, right first: right down", m.buttonDown(.right, at: 0, location: origin), .swallow)
            check("chord, right first: left down", m.buttonDown(.left, at: 0.05, location: origin), .armChord)
            check("chord, right first: right up", m.buttonUp(.right, at: 0.10, location: origin), .swallow)
            check("chord, right first: left up", m.buttonUp(.left, at: 0.15, location: origin), .chordCompleted)
        }

        // 6. The gesture as two consecutive clicks.
        do {
            var m = ChordStateMachine()
            check("chord by clicks: left down", m.buttonDown(.left, at: 0, location: origin), .pass)
            check("chord by clicks: left up", m.buttonUp(.left, at: 0.05, location: origin), .pass)
            check("chord by clicks: right down", m.buttonDown(.right, at: 0.10, location: origin), .armChord)
            check("chord by clicks: right up", m.buttonUp(.right, at: 0.15, location: origin), .chordCompleted)
        }

        // 7. Dragging the mouse is not a gesture.
        do {
            var m = ChordStateMachine()
            check("drag: left down", m.buttonDown(.left, at: 0, location: origin), .pass)
            check("drag: left up (pointer moved)", m.buttonUp(.left, at: 0.30, location: moved), .pass)
            check("drag: right down is not a gesture", m.buttonDown(.right, at: 0.35, location: moved), .swallow)
        }

        // 8. A right click much later than the left one is not a gesture.
        do {
            var m = ChordStateMachine()
            check("slow right click: left down", m.buttonDown(.left, at: 0, location: origin), .pass)
            check("slow right click: left up", m.buttonUp(.left, at: 0.05, location: origin), .pass)
            check("slow right click: right down is not a gesture", m.buttonDown(.right, at: 1.0, location: origin), .swallow)
        }

        // 9. Holding the left button for a long time is not a gesture.
        do {
            var m = ChordStateMachine()
            check("long hold: left down", m.buttonDown(.left, at: 0, location: origin), .pass)
            check("long hold: right down is not a gesture", m.buttonDown(.right, at: 1.0, location: origin), .swallow)
        }

        // 10. The state is reset after a gesture.
        do {
            var m = ChordStateMachine()
            _ = m.buttonDown(.left, at: 0, location: origin)
            _ = m.buttonDown(.right, at: 0.05, location: origin)
            _ = m.buttonUp(.left, at: 0.10, location: origin)
            _ = m.buttonUp(.right, at: 0.15, location: origin)
            check("after the gesture: plain click", m.buttonDown(.left, at: 1.0, location: origin), .pass)
            check("after the gesture: plain right click", m.buttonDown(.right, at: 1.5, location: origin), .swallow)
            check("after the gesture: the right click is handed back", m.buttonUp(.right, at: 1.55, location: origin), .repostBufferedDown)
        }

        // 11. The middle button never takes part in the gesture.
        do {
            var m = ChordStateMachine()
            check("middle button: down", m.buttonDown(.other, at: 0, location: origin), .pass)
            check("middle button: up", m.buttonUp(.other, at: 0.05, location: origin), .pass)
        }

        print("")
        if failures == 0 {
            print("All checks passed.")
        } else {
            print("Failed checks: \(failures)")
        }
        return failures == 0 ? 0 : 1
    }
}
