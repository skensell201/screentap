import Darwin
import Foundation

/// Manages the "launch at login" behaviour through a LaunchAgent.
///
/// A LaunchAgent is used instead of `SMAppService` because it works regardless of
/// where the `.app` bundle lives and does not require a stable code signature.
final class LaunchAgentController {
    static let label = "xyz.screentap.ScreenTap"

    private var plistURL: URL {
        let directory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents", isDirectory: true)
        return directory.appendingPathComponent("\(Self.label).plist")
    }

    var isEnabled: Bool {
        FileManager.default.fileExists(atPath: plistURL.path)
    }

    func enable(executablePath: String) throws {
        let directory = plistURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let properties: [String: Any] = [
            "Label": Self.label,
            "ProgramArguments": [executablePath],
            "RunAtLoad": true,
            "KeepAlive": false,
            "ProcessType": "Interactive",
        ]

        let data = try PropertyListSerialization.data(
            fromPropertyList: properties,
            format: .xml,
            options: 0
        )
        try data.write(to: plistURL)

        runLaunchctl(arguments: ["bootstrap", "gui/\(getuid())", plistURL.path])
        Log.d("Автозапуск включён: \(plistURL.path)")
    }

    func disable() {
        runLaunchctl(arguments: ["bootout", "gui/\(getuid())/\(Self.label)"])
        try? FileManager.default.removeItem(at: plistURL)
        Log.d("Автозапуск выключен")
    }

    private func runLaunchctl(arguments: [String]) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        task.arguments = arguments
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        do {
            try task.run()
        } catch {
            Log.e("Не удалось выполнить launchctl \(arguments.joined(separator: " ")): \(error.localizedDescription)")
        }
    }
}
