import SwiftUI
import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins

// MARK: - 024 QR-код

struct QrGenTool: View {
    @ViewState private var text = ""
    @ViewState private var image: NSImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ToolInOut(placeholder: L("Текст или ссылка"), input: $text)
            Button(L("Сделать QR")) { make() }.buttonStyle(.bordered).controlSize(.small)
            if let image {
                Image(nsImage: image)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 140)
                Button(L("Сохранить PNG")) { save(image) }.buttonStyle(.bordered).controlSize(.small)
            }
        }
    }

    private func make() {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { image = nil; return }
        let scale = 10.0
        let scaled = output.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let context = CIContext()
        guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else { image = nil; return }
        image = NSImage(cgImage: cgImage, size: NSSize(width: scaled.extent.width, height: scaled.extent.height))
    }

    private func save(_ image: NSImage) {
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return }
        let target = ToolOutput.uniqueURL(name: "QR.png")
        try? png.write(to: target)
    }
}

// MARK: - 025 Пипетка цвета

struct ColorPickerTool: View {
    @ViewState private var hex = ""
    @ViewState private var hint = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(L("Взять цвет с экрана")) { sample() }.buttonStyle(.bordered).controlSize(.small)
            if !hex.isEmpty {
                HStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 6).fill(Color(hex: hex) ?? .clear).frame(width: 32, height: 32)
                    ToolCopyRow(text: hex)
                }
            }
            Text(hint).font(.caption2).foregroundStyle(.secondary)
        }
    }

    private func sample() {
        let sampler = NSColorSampler()
        hint = L("Кликни по пикселю на экране")
        sampler.show { color in
            guard let color else {
                hint = ""
                return
            }
            let red = Int(color.redComponent * 255)
            let green = Int(color.greenComponent * 255)
            let blue = Int(color.blueComponent * 255)
            hex = String(format: "#%02X%02X%02X", red, green, blue)
            hint = ""
        }
    }
}

// MARK: - 027 Палитра из картинки

struct PaletteImgTool: View {
    @ViewState private var swatches: [(String, Color)] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            DropZone(hint: L("Перетащи картинку — покажу палитру")) { url in extract(url) }
            if !swatches.isEmpty {
                HStack(spacing: 6) {
                    ForEach(Array(swatches.enumerated()), id: \.offset) { pair in
                        VStack(spacing: 2) {
                            RoundedRectangle(cornerRadius: 5)
                                .fill(pair.element.1)
                                .frame(width: 34, height: 34)
                            Text(pair.element.0).font(.system(size: 7, design: .monospaced))
                        }
                        .onTapGesture { ToolClipboard.copy(pair.element.0) }
                    }
                }
                Text(L("Клик по цвету копирует hex")).font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    private func extract(_ url: URL) {
        guard let image = NSImage(contentsOf: url),
              let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return }
        var buckets: [String: (count: Int, red: Int, green: Int, blue: Int)] = [:]
        let step = max(rep.pixelsWide, rep.pixelsHigh) / 24
        for x in stride(from: 0, to: rep.pixelsWide, by: max(step, 1)) {
            for y in stride(from: 0, to: rep.pixelsHigh, by: max(step, 1)) {
                guard let color = rep.colorAt(x: x, y: y) else { continue }
                let red = Int(color.redComponent * 255)
                let green = Int(color.greenComponent * 255)
                let blue = Int(color.blueComponent * 255)
                let key = "\(red / 32)-\(green / 32)-\(blue / 32)"
                var bucket = buckets[key] ?? (0, 0, 0, 0)
                bucket.count += 1
                bucket.red += red
                bucket.green += green
                bucket.blue += blue
                buckets[key] = bucket
            }
        }
        let top = buckets.values.sorted { $0.count > $1.count }.prefix(6)
        swatches = top.map { bucket in
            let red = bucket.red / max(bucket.count, 1)
            let green = bucket.green / max(bucket.count, 1)
            let blue = bucket.blue / max(bucket.count, 1)
            let hex = String(format: "#%02X%02X%02X", red, green, blue)
            return (hex, Color(red: Double(red) / 255, green: Double(green) / 255, blue: Double(blue) / 255))
        }
    }
}

// MARK: - 028 Экранная линейка

final class RulerWindowController {
    static let shared = RulerWindowController()
    private var window: NSWindow?

    func show() {
        if let window { window.makeKeyAndOrderFront(nil); return }
        guard let screen = NSScreen.main else { return }
        let window = NSWindow(contentRect: screen.frame,
                              styleMask: [.borderless],
                              backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = .floating
        window.ignoresMouseEvents = false
        let view = RulerView(frame: screen.frame)
        window.contentView = view
        window.makeKeyAndOrderFront(nil)
        self.window = window
    }

    func close() {
        window?.orderOut(nil)
        window = nil
    }
}

final class RulerView: NSView {
    private var start: NSPoint?
    private var current: NSPoint?
    private var trackingArea: NSTrackingArea?

    override var acceptsFirstResponder: Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(rect: bounds,
                                  options: [.mouseMoved, .activeAlways],
                                  owner: self)
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseDown(with event: NSEvent) {
        start = convert(event.locationInWindow, from: nil)
        current = start
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        current = convert(event.locationInWindow, from: nil)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        current = convert(event.locationInWindow, from: nil)
        needsDisplay = true
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { RulerWindowController.shared.close() }
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.06).setFill()
        dirtyRect.fill()
        guard let start, let current else { return }
        let path = NSBezierPath()
        path.move(to: start)
        path.line(to: current)
        NSColor.systemBlue.setStroke()
        path.lineWidth = 2
        path.stroke()
        let distance = hypot(current.x - start.x, current.y - start.y)
        let text = String(format: "%.0f px", distance)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 14, weight: .semibold),
            .foregroundColor: NSColor.white,
        ]
        let string = NSAttributedString(string: text, attributes: attributes)
        let center = NSPoint(x: (start.x + current.x) / 2 + 8, y: (start.y + current.y) / 2 + 8)
        string.draw(at: center)
    }
}

struct ScreenRulerTool: View {
    @ViewState private var hint = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(L("Показать линейку")) { RulerWindowController.shared.show() }
                .buttonStyle(.bordered).controlSize(.small)
            Button(L("Убрать линейку")) { RulerWindowController.shared.close() }
                .buttonStyle(.bordered).controlSize(.small)
            Text(L("Клик и тянуть — покажет расстояние в пикселях. Esc закрывает"))
                .font(.caption2).foregroundStyle(.secondary)
        }
    }
}
