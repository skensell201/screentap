import AppKit
import CoreGraphics
import ScreenCaptureKit

enum CaptureError: LocalizedError {
    case screenRecordingDenied
    case noDisplay
    case captureFailed
    case emptyRegion

    var errorDescription: String? {
        switch self {
        case .screenRecordingDenied:
            return "Нет доступа к записи экрана. Разрешите его в «Системных настройках → Конфиденциальность и безопасность → Запись экрана»."
        case .noDisplay:
            return "Не удалось определить дисплей для выделенной области."
        case .captureFailed:
            return "Не удалось захватить изображение экрана."
        case .emptyRegion:
            return "Выделенная область оказалась пустой."
        }
    }
}

/// Captures the contents of a rectangle of the screen.
final class ScreenCapturer {
    /// Captures `region` given in global Cocoa coordinates (origin bottom-left).
    func capture(region: CGRect) async throws -> CGImage {
        guard Permissions.screenRecordingGranted else { throw CaptureError.screenRecordingDenied }
        guard let screen = ScreenMapper.screen(for: region) else { throw CaptureError.noDisplay }

        if #available(macOS 14.0, *) {
            do {
                let image = try await captureWithScreenCaptureKit(screen: screen)
                return try crop(image, region: region, screen: screen)
            } catch {
                Log.e("ScreenCaptureKit не сработал (\(error.localizedDescription)) — пробую запасной путь")
            }
        }

        return try captureWithCoreGraphics(region: region)
    }

    // MARK: - ScreenCaptureKit

    @available(macOS 14.0, *)
    private func captureWithScreenCaptureKit(screen: NSScreen) async throws -> CGImage {
        let displayID = ScreenMapper.displayID(of: screen)
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
            throw CaptureError.noDisplay
        }

        // A display filter without excluded windows captures the whole display
        // including the wallpaper and the Dock.
        let filter = SCContentFilter(display: display, excludingWindows: [])
        let configuration = SCStreamConfiguration()
        configuration.showsCursor = false
        configuration.capturesAudio = false

        // Without an explicit size ScreenCaptureKit returns a 1920x1080 image and
        // stretches the content of the display. The native pixel size keeps the
        // aspect ratio intact, which matters for the cropping below.
        if let mode = CGDisplayCopyDisplayMode(displayID) {
            configuration.width = mode.pixelWidth
            configuration.height = mode.pixelHeight
        }
        configuration.scalesToFit = false

        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
        guard image.width > 0, image.height > 0 else { throw CaptureError.captureFailed }
        Log.d("SCK вернул изображение \(image.width)×\(image.height), экран \(Int(screen.frame.width))×\(Int(screen.frame.height))")
        return image
    }

    // MARK: - Legacy fallback

    private func captureWithCoreGraphics(region: CGRect) throws -> CGImage {
        let options: CGWindowListOption = [.optionOnScreenOnly]
        let listOptions: CGWindowImageOption = [.boundsIgnoreFraming, .bestResolution]
        guard let image = CGWindowListCreateImage(region, options, CGWindowID(0), listOptions) else {
            throw CaptureError.captureFailed
        }
        return image
    }

    // MARK: - Cropping

    /// Cuts the requested region out of a full display image.
    private func crop(_ image: CGImage, region: CGRect, screen: NSScreen) throws -> CGImage {
        let scaleX = CGFloat(image.width) / screen.frame.width
        let scaleY = CGFloat(image.height) / screen.frame.height

        let localX = region.minX - screen.frame.minX
        let localY = screen.frame.maxY - region.maxY

        var cropRect = CGRect(
            x: localX * scaleX,
            y: localY * scaleY,
            width: region.width * scaleX,
            height: region.height * scaleY
        )
        cropRect = cropRect.intersection(CGRect(x: 0, y: 0, width: image.width, height: image.height))
        Log.d("Кадрирование: масштаб \(scaleX)×\(scaleY), прямоугольник \(cropRect)")

        guard cropRect.width >= 1, cropRect.height >= 1, let cropped = image.cropping(to: cropRect) else {
            throw CaptureError.emptyRegion
        }
        return cropped
    }
}

/// Helpers that connect `NSScreen` objects with display identifiers.
enum ScreenMapper {
    /// The screen with the largest overlap with `region`.
    static func screen(for region: CGRect) -> NSScreen? {
        let screens = NSScreen.screens
        guard !screens.isEmpty else { return nil }
        return screens.max { a, b in
            overlapArea(a.frame, region) < overlapArea(b.frame, region)
        }
    }

    static func displayID(of screen: NSScreen) -> CGDirectDisplayID {
        let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
        return number?.uint32Value ?? 0
    }

    private static func overlapArea(_ a: CGRect, _ b: CGRect) -> CGFloat {
        let intersection = a.intersection(b)
        guard !intersection.isNull else { return 0 }
        return intersection.width * intersection.height
    }
}
