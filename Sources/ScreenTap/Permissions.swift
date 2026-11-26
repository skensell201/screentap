import AppKit
import ApplicationServices
import CoreGraphics

/// The permissions ScreenTap needs from the user.
enum Permissions {
    /// Required for capturing the screen contents.
    static var screenRecordingGranted: Bool {
        CGPreflightScreenCaptureAccess()
    }

    /// Required for suppressing the context menu of the application under the cursor.
    static var accessibilityGranted: Bool {
        AXIsProcessTrusted()
    }

    /// Shows the system prompt for the Accessibility permission.
    static func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        _ = AXIsProcessTrustedWithOptions(options as CFDictionary)
    }

    static func openScreenRecordingSettings() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")
    }

    static func openAccessibilitySettings() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    }

    private static func open(_ string: String) {
        guard let url = URL(string: string) else { return }
        NSWorkspace.shared.open(url)
    }
}
