#!/usr/bin/env swift
//
// Renders an illustration of the selection overlay.
//
// The illustration is drawn from scratch instead of being captured from a real
// screen, so that no private desktop content ends up in the repository.
//
//   swift Scripts/render-preview.swift <output.png>

import AppKit
import CoreGraphics
import Foundation

let outputPath = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "docs/overlay.png"

let width = 1400
let height = 880

guard let context = CGContext(
    data: nil,
    width: width,
    height: height,
    bitsPerComponent: 8,
    bytesPerRow: 0,
    space: CGColorSpaceCreateDeviceRGB(),
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else {
    FileHandle.standardError.write(Data("Could not create the graphics context\n".utf8))
    exit(1)
}

let bounds = CGRect(x: 0, y: 0, width: width, height: height)

// --- Mock desktop -----------------------------------------------------------

let gradient = CGGradient(
    colorsSpace: CGColorSpaceCreateDeviceRGB(),
    colors: [
        CGColor(red: 0.13, green: 0.10, blue: 0.26, alpha: 1),
        CGColor(red: 0.06, green: 0.07, blue: 0.14, alpha: 1),
    ] as CFArray,
    locations: [0, 1]
)!
context.drawLinearGradient(
    gradient,
    start: CGPoint(x: 0, y: height),
    end: CGPoint(x: width, y: 0),
    options: []
)

// A few abstract window shapes to make the backdrop read as a desktop.
func drawMockWindow(_ rect: CGRect, opacity: CGFloat) {
    context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.05 * opacity))
    context.fill(rect)
    context.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.10 * opacity))
    context.setLineWidth(1)
    context.stroke(rect.insetBy(dx: 0.5, dy: 0.5))
}

drawMockWindow(CGRect(x: 90, y: 120, width: 520, height: 340), opacity: 1)
drawMockWindow(CGRect(x: 700, y: 430, width: 610, height: 330), opacity: 0.8)
drawMockWindow(CGRect(x: 180, y: 540, width: 380, height: 220), opacity: 0.6)

// --- Overlay dimming --------------------------------------------------------

context.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 0.35))
context.fill(bounds)

// --- Selection rectangle ----------------------------------------------------

let selection = CGRect(x: 400, y: 250, width: 620, height: 390)
let accent = CGColor(red: 0.25, green: 0.60, blue: 1.0, alpha: 0.95)

context.setStrokeColor(accent)
context.setLineWidth(2)
context.stroke(selection.insetBy(dx: 1, dy: 1))

context.setFillColor(accent)
let handle: CGFloat = 4
for point in [
    CGPoint(x: selection.minX, y: selection.minY), CGPoint(x: selection.maxX, y: selection.minY),
    CGPoint(x: selection.minX, y: selection.maxY), CGPoint(x: selection.maxX, y: selection.maxY),
] {
    context.fillEllipse(in: CGRect(x: point.x - handle, y: point.y - handle, width: handle * 2, height: handle * 2))
}

// --- Size HUD ---------------------------------------------------------------

let hudText = "800 × 500"
let attributes: [NSAttributedString.Key: Any] = [
    .font: NSFont.monospacedDigitSystemFont(ofSize: 14, weight: .medium),
    .foregroundColor: NSColor.white,
]
let attributed = NSAttributedString(string: hudText, attributes: attributes)
let textSize = attributed.size()
let padding: CGFloat = 10
let hud = CGRect(
    x: selection.minX,
    y: selection.minY - 36,
    width: textSize.width + padding * 2,
    height: textSize.height + padding
)

context.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 0.65))
context.addPath(CGPath(roundedRect: hud, cornerWidth: 6, cornerHeight: 6, transform: nil))
context.fillPath()

let textImage = NSImage(size: textSize)
textImage.lockFocus()
attributed.draw(at: .zero)
textImage.unlockFocus()

if let cgImage = textImage.cgImage(forProposedRect: nil, context: nil, hints: nil) {
    context.draw(cgImage, in: CGRect(x: hud.minX + padding, y: hud.minY + padding / 2, width: textSize.width, height: textSize.height))
}

// --- Crosshair --------------------------------------------------------------

context.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.5))
context.setLineWidth(1)
let crosshair = CGPoint(x: 1010, y: 150)
context.move(to: CGPoint(x: crosshair.x, y: 0))
context.addLine(to: CGPoint(x: crosshair.x, y: CGFloat(height)))
context.move(to: CGPoint(x: 0, y: crosshair.y))
context.addLine(to: CGPoint(x: CGFloat(width), y: crosshair.y))
context.strokePath()

// --- Output -----------------------------------------------------------------

guard let image = context.makeImage() else {
    FileHandle.standardError.write(Data("Could not produce the final image\n".utf8))
    exit(1)
}

let rep = NSBitmapImageRep(cgImage: image)
guard let png = rep.representation(using: .png, properties: [:]) else {
    FileHandle.standardError.write(Data("Could not encode the PNG\n".utf8))
    exit(1)
}

try png.write(to: URL(fileURLWithPath: outputPath))
print("Written \(outputPath) (\(width)×\(height))")
