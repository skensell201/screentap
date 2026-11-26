import AppKit
import CoreGraphics

/// Writes the captured image into the general pasteboard.
enum ClipboardWriter {
    /// Returns `true` when the image was written successfully.
    @discardableResult
    static func write(_ image: CGImage) -> Bool {
        let rep = NSBitmapImageRep(cgImage: image)
        guard let png = rep.representation(using: .png, properties: [:]) else {
            Log.e("Could not encode the image as PNG")
            return false
        }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setData(png, forType: .png)

        // Some applications still expect a TIFF representation.
        if let tiff = rep.representation(using: .tiff, properties: [:]) {
            pasteboard.setData(tiff, forType: .tiff)
        }

        Log.d("Screenshot (\(image.width)×\(image.height)) copied to the clipboard")
        return true
    }

    /// Writes the image into the pasteboard and additionally saves it as a file.
    @discardableResult
    static func write(_ image: CGImage, alsoSaveTo path: String) -> Bool {
        let rep = NSBitmapImageRep(cgImage: image)
        if let png = rep.representation(using: .png, properties: [:]) {
            try? png.write(to: URL(fileURLWithPath: path))
        }
        return write(image)
    }
}

/// Short audio feedback.
enum FeedbackSound {
    static func playSuccess() {
        if let sound = NSSound(named: "Tink") {
            sound.play()
        } else {
            NSSound.beep()
        }
    }

    static func playFailure() {
        NSSound.beep()
    }
}
