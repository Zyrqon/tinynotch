import AppKit
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

/// `Notchly --gif <файл.gif> [--lang en]` рисует GIF для README: остров раскрывается, стоит и сворачивается.
/// Кадры считаются по тем же пружинам, что в IslandMetrics, поэтому GIF совпадает с настоящей анимацией,
/// а экран записывать не нужно. Данные вымышленные, как в снапшотах.
enum ReadmeGIF {
    private static let fps = 30.0

    @MainActor
    static func render(to url: URL) {
        SnapshotFlags.isRendering = true
        let model = IslandModel(persistent: false)
        let notch = CGSize(width: 185, height: 32)
        model.notchSize = notch
        let art = NSImage(size: NSSize(width: 300, height: 300), flipped: false) { rect in
            NSGradient(colors: [.systemPink, .systemOrange, .systemPurple])?.draw(in: rect, angle: 45)
            return true
        }
        model.media.debugSet(title: "Blinding Lights", artist: "The Weeknd", album: "After Hours",
                             duration: 200, elapsed: 74, playing: true, artwork: art, bundleID: "com.apple.Music")
        model.weather.debugSet(Weather(temperature: 18, high: 21, low: 12, code: 1, isDay: true,
                                       city: Loc.pick("Берлин", "Berlin"), latitude: 52.52, longitude: 13.40))
        model.batteries.debugSet(devices: [], phone: nil, mac: BatteryInfo(percent: 82, charging: false))
        model.tab = .home

        let size = IslandMetrics.windowSize
        let root = ZStack(alignment: .top) {
            // Кусочек «рабочего стола» со строкой меню, чтобы было видно, откуда выходит остров.
            LinearGradient(colors: [Color(red: 0.16, green: 0.2, blue: 0.42), Color(red: 0.42, green: 0.25, blue: 0.5)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            Color.black.opacity(0.18).frame(height: notch.height).frame(maxHeight: .infinity, alignment: .top)
            IslandRootView(model: model, media: model.media, settings: model.settings)
        }
        .frame(width: size.width, height: size.height)
        let host = NSHostingView(rootView: root)
        host.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: host.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = host

        let collapsed = (size: CGSize(width: notch.width + 14, height: notch.height), top: CGFloat(7), bottom: CGFloat(11))
        let expanded = (size: CGSize(width: IslandMetrics.expandedWidth + 28, height: notch.height + IslandMetrics.expandedContentHeight),
                        top: CGFloat(14), bottom: CGFloat(34))
        func frame(shape p: Double, content c: Double) -> IslandModel.DebugFrame {
            let k = CGFloat(p)
            return .init(size: CGSize(width: collapsed.size.width + (expanded.size.width - collapsed.size.width) * k,
                                      height: collapsed.size.height + (expanded.size.height - collapsed.size.height) * k),
                         top: collapsed.top + (expanded.top - collapsed.top) * k,
                         bottom: collapsed.bottom + (expanded.bottom - collapsed.bottom) * k,
                         content: c)
        }

        var frames: [(IslandModel.DebugFrame, Bool)] = []  // кадр и «остров раскрыт»
        let step = 1 / fps
        for _ in 0..<12 { frames.append((frame(shape: 0, content: 0), false)) }
        // Открытие: шторка — пружина IslandMetrics.open, виджеты — easeOut 0.3 с после паузы.
        for i in 0..<Int(0.9 * fps) {
            let t = Double(i) * step
            let content = easeOut(max(0, t - IslandMetrics.contentInDelay) / 0.3)
            frames.append((frame(shape: spring(t, response: 0.44, damping: 0.9), content: content), true))
        }
        for _ in 0..<Int(1.6 * fps) { frames.append((frame(shape: 1, content: 1), true)) }
        // Закрытие: сначала гаснет содержимое, потом форма без отскока уходит в вырез.
        for i in 0..<Int(0.85 * fps) {
            let t = Double(i) * step
            let content = 1 - easeOut(t / 0.14)
            let shape = t < IslandMetrics.closeDelay ? 1 : 1 - spring(t - IslandMetrics.closeDelay, response: 0.5, damping: 1)
            frames.append((frame(shape: shape, content: content), shape > 0.02))
        }
        for _ in 0..<12 { frames.append((frame(shape: 0, content: 0), false)) }

        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.gif.identifier as CFString,
                                                                frames.count, nil) else { return }
        CGImageDestinationSetProperties(destination, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
        let delay = [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: step]] as CFDictionary

        // Первый проход: даём SwiftUI загрузить раскрытое содержимое, чтобы в первых кадрах не было пустоты.
        model.isExpanded = true
        model.expandedContentVisible = true
        model.debugFrame = frame(shape: 1, content: 1)
        // Если вкладка выбрана в момент первого появления шапки, офскрин-рендер теряет её иконку.
        // Поэтому сначала показываем другую вкладку и переключаемся — как это происходит вживую.
        model.tab = .music
        RunLoop.main.run(until: Date().addingTimeInterval(0.6))
        model.tab = .home
        RunLoop.main.run(until: Date().addingTimeInterval(1.2))

        // Содержимое всё время на месте (иначе шапка появлялась бы заново), его видимость задаёт кадр.
        for (debug, _) in frames {
            model.debugFrame = debug
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
            host.layoutSubtreeIfNeeded()
            guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { continue }
            host.cacheDisplay(in: host.bounds, to: rep)
            // Хранить кадры в 2x незачем: GIF получился бы огромным.
            guard let full = rep.cgImage, let image = downscale(full, to: size) else { continue }
            CGImageDestinationAddImage(destination, image, delay)
        }
        CGImageDestinationFinalize(destination)
    }

    /// Пружина SwiftUI с заданными response и dampingFraction, от 0 до 1.
    private static func spring(_ t: Double, response: Double, damping: Double) -> Double {
        let omega = 2 * Double.pi / response
        if damping >= 1 { return 1 - (1 + omega * t) * exp(-omega * t) }
        let wd = omega * sqrt(1 - damping * damping)
        return 1 - exp(-damping * omega * t) * (cos(wd * t) + damping * omega / wd * sin(wd * t))
    }

    private static func easeOut(_ x: Double) -> Double {
        let t = min(max(x, 0), 1)
        return 1 - pow(1 - t, 3)
    }

    private static func downscale(_ image: CGImage, to size: CGSize) -> CGImage? {
        guard let ctx = CGContext(data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8,
                                  bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue) else { return nil }
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(origin: .zero, size: size))
        return ctx.makeImage()
    }
}

