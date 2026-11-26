#!/usr/bin/env swift
//
// Размещает исходную иконку на прозрачном холсте 1024x1024 с полями,
// как того требует macOS для иконок приложений.
//
//   swift Scripts/pad-icon.swift <вход.png> <выход.png>

import AppKit
import CoreGraphics
import Foundation

let arguments = CommandLine.arguments
guard arguments.count == 3 else {
    FileHandle.standardError.write(Data("Использование: pad-icon.swift <вход> <выход>\n".utf8))
    exit(2)
}

let inputURL = URL(fileURLWithPath: arguments[1])
let outputURL = URL(fileURLWithPath: arguments[2])

guard let source = NSImage(contentsOf: inputURL),
      let sourceCG = source.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
    FileHandle.standardError.write(Data("Не удалось прочитать изображение \(inputURL.path)\n".utf8))
    exit(1)
}

// Каноническое полотно macOS — 1024x1024, сама иконка занимает ~82% полотна.
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
    FileHandle.standardError.write(Data("Не удалось создать графический контекст\n".utf8))
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
    FileHandle.standardError.write(Data("Не удалось получить итоговое изображение\n".utf8))
    exit(1)
}

let rep = NSBitmapImageRep(cgImage: output)
guard let png = rep.representation(using: .png, properties: [:]) else {
    FileHandle.standardError.write(Data("Не удалось закодировать PNG\n".utf8))
    exit(1)
}

try png.write(to: outputURL)
print("    \(inputURL.lastPathComponent) -> \(outputURL.lastPathComponent) (\(canvasSize)x\(canvasSize))")
