import AppKit
import Foundation

/// Minimal logger. Verbose output is enabled with the `--debug` flag so that the
/// app stays silent when it runs as a menu bar accessory.
enum Log {
    static let debugEnabled = CommandLine.arguments.contains("--debug")

    static func d(_ message: String) {
        guard debugEnabled else { return }
        let stamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        print("[\(stamp)] [ScreenTap] \(message)")
        fflush(stdout)
    }

    static func e(_ message: String) {
        print("[ScreenTap] \(message)")
        fflush(stdout)
    }
}
