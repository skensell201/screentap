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
                print("✗ \(name): ожидалось \(expected.map { "\($0)" } ?? "nil"), получено \(actual.map { "\($0)" } ?? "nil")")
            } else {
                print("✓ \(name)")
            }
        }

        let origin = CGPoint(x: 100, y: 100)
        let moved = CGPoint(x: 400, y: 300)

        // 1. Обычный клик левой кнопкой.
        do {
            var m = ChordStateMachine()
            check("обычный клик левой кнопкой (down)", m.buttonDown(.left, at: 0, location: origin), .pass)
            check("обычный клик левой кнопкой (up)", m.buttonUp(.left, at: 0.05, location: origin), .pass)
        }

        // 2. Обычный правый клик: нажатие поглощается и возвращается в систему.
        do {
            var m = ChordStateMachine()
            check("правый клик (down поглощается)", m.buttonDown(.right, at: 0, location: origin), .swallow)
            check("правый клик (up возвращает нажатие)", m.buttonUp(.right, at: 0.05, location: origin), .repostBufferedDown)
        }

        // 3. Правый клик с удержанием: возврат по таймеру.
        do {
            var m = ChordStateMachine()
            check("правый клик (down поглощается)", m.buttonDown(.right, at: 0, location: origin), .swallow)
            check("правый клик (таймер возвращает нажатие)", m.tick(now: 0.30), .repostBufferedDown)
        }

        // 4. Жест левой кнопкой вперёд.
        do {
            var m = ChordStateMachine()
            check("chord слева: left down", m.buttonDown(.left, at: 0, location: origin), .pass)
            check("chord слева: right down", m.buttonDown(.right, at: 0.05, location: origin), .armChord)
            check("chord слева: left up", m.buttonUp(.left, at: 0.10, location: origin), .swallow)
            check("chord слева: right up", m.buttonUp(.right, at: 0.15, location: origin), .chordCompleted)
        }

        // 5. Жест правой кнопкой вперёд.
        do {
            var m = ChordStateMachine()
            check("chord справа: right down", m.buttonDown(.right, at: 0, location: origin), .swallow)
            check("chord справа: left down", m.buttonDown(.left, at: 0.05, location: origin), .armChord)
            check("chord справа: right up", m.buttonUp(.right, at: 0.10, location: origin), .swallow)
            check("chord справа: left up", m.buttonUp(.left, at: 0.15, location: origin), .chordCompleted)
        }

        // 6. Жест последовательными кликами.
        do {
            var m = ChordStateMachine()
            check("chord кликами: left down", m.buttonDown(.left, at: 0, location: origin), .pass)
            check("chord кликами: left up", m.buttonUp(.left, at: 0.05, location: origin), .pass)
            check("chord кликами: right down", m.buttonDown(.right, at: 0.10, location: origin), .armChord)
            check("chord кликами: right up", m.buttonUp(.right, at: 0.15, location: origin), .chordCompleted)
        }

        // 7. Перетаскивание мышью не считается жестом.
        do {
            var m = ChordStateMachine()
            check("drag: left down", m.buttonDown(.left, at: 0, location: origin), .pass)
            check("drag: left up (смещение)", m.buttonUp(.left, at: 0.30, location: moved), .pass)
            check("drag: right down не жест", m.buttonDown(.right, at: 0.35, location: moved), .swallow)
        }

        // 8. Правый клик сильно позже левого — не жест.
        do {
            var m = ChordStateMachine()
            check("медленный правый клик: left down", m.buttonDown(.left, at: 0, location: origin), .pass)
            check("медленный правый клик: left up", m.buttonUp(.left, at: 0.05, location: origin), .pass)
            check("медленный правый клик: right down не жест", m.buttonDown(.right, at: 1.0, location: origin), .swallow)
        }

        // 9. Долгое удержание левой кнопки — не жест.
        do {
            var m = ChordStateMachine()
            check("долгое удержание: left down", m.buttonDown(.left, at: 0, location: origin), .pass)
            check("долгое удержание: right down не жест", m.buttonDown(.right, at: 1.0, location: origin), .swallow)
        }

        // 10. После жеста состояние сбрасывается.
        do {
            var m = ChordStateMachine()
            _ = m.buttonDown(.left, at: 0, location: origin)
            _ = m.buttonDown(.right, at: 0.05, location: origin)
            _ = m.buttonUp(.left, at: 0.10, location: origin)
            _ = m.buttonUp(.right, at: 0.15, location: origin)
            check("после жеста: обычный клик", m.buttonDown(.left, at: 1.0, location: origin), .pass)
            check("после жеста: обычный правый клик", m.buttonDown(.right, at: 1.5, location: origin), .swallow)
            check("после жеста: правый клик возвращается", m.buttonUp(.right, at: 1.55, location: origin), .repostBufferedDown)
        }

        // 11. Средняя кнопка никогда не участвует в жесте.
        do {
            var m = ChordStateMachine()
            check("средняя кнопка: down", m.buttonDown(.other, at: 0, location: origin), .pass)
            check("средняя кнопка: up", m.buttonUp(.other, at: 0.05, location: origin), .pass)
        }

        print("")
        if failures == 0 {
            print("Все проверки пройдены.")
        } else {
            print("Провалено проверок: \(failures)")
        }
        return failures == 0 ? 0 : 1
    }
}
