#!/usr/bin/env swift
// Рисует иконку Notchly (буква N с «островом» над ней) и собирает Resources/AppIcon.icns.
// Запуск: swift scripts/make-icon.swift
import AppKit

let root = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().deletingLastPathComponent()
let side: CGFloat = 1024

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255,
            blue: CGFloat(hex & 0xff) / 255, alpha: alpha)
}

func roundedRect(_ rect: NSRect, top: CGFloat, bottom: CGFloat) -> NSBezierPath {
    // Координаты перевёрнуты (y вниз): «верх» — minY.
    let p = NSBezierPath()
    p.move(to: NSPoint(x: rect.minX + top, y: rect.minY))
    p.line(to: NSPoint(x: rect.maxX - top, y: rect.minY))
    p.curve(to: NSPoint(x: rect.maxX, y: rect.minY + top), controlPoint1: NSPoint(x: rect.maxX, y: rect.minY),
            controlPoint2: NSPoint(x: rect.maxX, y: rect.minY))
    p.line(to: NSPoint(x: rect.maxX, y: rect.maxY - bottom))
    p.curve(to: NSPoint(x: rect.maxX - bottom, y: rect.maxY), controlPoint1: NSPoint(x: rect.maxX, y: rect.maxY),
            controlPoint2: NSPoint(x: rect.maxX, y: rect.maxY))
    p.line(to: NSPoint(x: rect.minX + bottom, y: rect.maxY))
    p.curve(to: NSPoint(x: rect.minX, y: rect.maxY - bottom), controlPoint1: NSPoint(x: rect.minX, y: rect.maxY),
            controlPoint2: NSPoint(x: rect.minX, y: rect.maxY))
    p.line(to: NSPoint(x: rect.minX, y: rect.minY + top))
    p.curve(to: NSPoint(x: rect.minX + top, y: rect.minY), controlPoint1: NSPoint(x: rect.minX, y: rect.minY),
            controlPoint2: NSPoint(x: rect.minX, y: rect.minY))
    p.close()
    return p
}

let image = NSImage(size: NSSize(width: side, height: side), flipped: true) { _ in
    let tile = NSRect(x: 100, y: 100, width: 824, height: 824)
    let squircle = NSBezierPath(roundedRect: tile, xRadius: 186, yRadius: 186)

    // Тень всей иконки, как у системных.
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = .black.withAlphaComponent(0.35)
    shadow.shadowBlurRadius = 24
    shadow.shadowOffset = NSSize(width: 0, height: 10)   // в перевёрнутых координатах «+» — вниз
    shadow.set()
    color(0x101218).setFill()
    squircle.fill()
    NSGraphicsContext.restoreGraphicsState()

    NSGraphicsContext.saveGraphicsState()
    squircle.addClip()

    // Почти чёрный фон.
    color(0x111111).setFill()
    tile.fill()

    // «N» со скруглёнными концами и «островом» над ней.
    let stroke: CGFloat = 68
    color(0xffffff).setFill()
    color(0xffffff).setStroke()
    let n = NSBezierPath()
    n.move(to: NSPoint(x: 382, y: 713))
    n.line(to: NSPoint(x: 382, y: 423))
    n.line(to: NSPoint(x: 642, y: 713))
    n.line(to: NSPoint(x: 642, y: 423))
    n.lineWidth = stroke
    n.lineCapStyle = .round
    n.lineJoinStyle = .round
    n.stroke()
    let island = NSRect(x: 402, y: 276, width: 220, height: stroke)
    NSBezierPath(roundedRect: island, xRadius: stroke / 2, yRadius: stroke / 2).fill()

    NSGraphicsContext.restoreGraphicsState()

    // Тонкая светлая кромка.
    color(0xffffff, 0.06).setStroke()
    squircle.lineWidth = 3
    squircle.stroke()
    return true
}

func png(_ size: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: size, height: size)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .high
    image.draw(in: NSRect(x: 0, y: 0, width: size, height: size))
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try! FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    try! png(base).write(to: iconset.appendingPathComponent("icon_\(base)x\(base).png"))
    try! png(base * 2).write(to: iconset.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
try! png(1024).write(to: root.appendingPathComponent("docs/icon.png"))

let out = root.appendingPathComponent("Resources/AppIcon.icns")
let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", iconset.path, "-o", out.path]
try! task.run()
task.waitUntilExit()
print(task.terminationStatus == 0 ? "Готово: \(out.path)" : "iconutil завершился с ошибкой")
