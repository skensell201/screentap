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

    /// Asks macOS for the screen recording permission.
    ///
    /// The grant is bound to the code requirement of the running binary, which is
    /// why it has to be requested from the app itself: an entry that was added
    /// to the System Settings list by hand may refer to an older signature.
    @discardableResult
    static func requestScreenRecording() -> Bool {
        let granted = CGRequestScreenCaptureAccess()
        Log.d("Screen recording request returned \(granted)")
        return granted
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
