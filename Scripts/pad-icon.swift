#!/usr/bin/env swift
//
// Places the source icon on a transparent 1024x1024 canvas with the margins
// macOS expects for application icons.
//
//   swift Scripts/pad-icon.swift <input.png> <output.png>

import AppKit
import CoreGraphics
import Foundation

let arguments = CommandLine.arguments
guard arguments.count == 3 else {
    FileHandle.standardError.write(Data("Usage: pad-icon.swift <input> <output>\n".utf8))
    exit(2)
}

let inputURL = URL(fileURLWithPath: arguments[1])
let outputURL = URL(fileURLWithPath: arguments[2])

guard let source = NSImage(contentsOf: inputURL),
      let sourceCG = source.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
    FileHandle.standardError.write(Data("Could not read the image \(inputURL.path)\n".utf8))
    exit(1)
}

// The canonical macOS canvas is 1024x1024, the icon itself takes ~82% of it.
let canvasSize = 1024
let insetRatio = 0.82
let targetSize = CGFloat(canvasSize) * insetRatio

guard let context = CGContext(
    data: nil,
    width: canvasSize,
    height: canvasSize,
    bitsPerComponent: 8,
    bytesPerRow: 0,
    space: CGColorSpaceCreateDeviceRGB(),
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else {
    FileHandle.standardError.write(Data("Could not create the graphics context\n".utf8))
    exit(1)
}

context.clear(CGRect(x: 0, y: 0, width: canvasSize, height: canvasSize))
context.interpolationQuality = .high

let scale = min(targetSize / CGFloat(sourceCG.width), targetSize / CGFloat(sourceCG.height))
let drawWidth = CGFloat(sourceCG.width) * scale
let drawHeight = CGFloat(sourceCG.height) * scale
let originX = (CGFloat(canvasSize) - drawWidth) / 2
let originY = (CGFloat(canvasSize) - drawHeight) / 2

context.draw(
    sourceCG,
    in: CGRect(x: originX, y: originY, width: drawWidth, height: drawHeight)
)

guard let output = context.makeImage() else {
    FileHandle.standardError.write(Data("Could not produce the final image\n".utf8))
    exit(1)
}

let rep = NSBitmapImageRep(cgImage: output)
guard let png = rep.representation(using: .png, properties: [:]) else {
    FileHandle.standardError.write(Data("Could not encode the PNG\n".utf8))
    exit(1)
}

try png.write(to: outputURL)
print("    \(inputURL.lastPathComponent) -> \(outputURL.lastPathComponent) (\(canvasSize)x\(canvasSize))")
