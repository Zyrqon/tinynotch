import AppKit
import SwiftUI
import CoreImage

/// Состояние «Сейчас играет» для любого плеера: Apple Music, Spotify, Яндекс Музыка,
/// YouTube Music (в браузере или десктоп-клиенте) и всё остальное, что публикует
/// системный Now Playing. Основной источник — MediaRemote через perl-адаптер,
/// запасной — AppleScript для Music и Spotify.
final class MediaController: ObservableObject {
    @Published private(set) var title = ""
    @Published private(set) var artist = ""
    @Published private(set) var album = ""
    @Published private(set) var duration: Double = 0
    @Published private(set) var elapsed: Double = 0
    @Published private(set) var timestamp = Date()
    @Published private(set) var isPlaying = false
    @Published private(set) var artwork: NSImage?
    @Published private(set) var accent: Color = .white
    /// Свечение вокруг обложки: сама обложка, размытая в прозрачное поле (считается один раз).
    @Published private(set) var glow: NSImage?
    /// Повтор текущего трека. Работает с любым плеером: у конца трека перематываем в начало.
    @Published private(set) var repeatOne = false
    @Published private(set) var bundleID: String?
    /// Показывать ли «живую активность» (обложка + эквалайзер) в свёрнутом острове.
    @Published private(set) var showsLiveActivity = false

    var onTrackChange: (() -> Void)?

    var hasTrack: Bool { !title.isEmpty }
    var trackID: String { "\(title)|\(artist)|\(album)" }
    /// Для шторки с названием: альбом часто приходит отдельным сообщением, из-за него шторка не должна появляться второй раз.
    var peekID: String { "\(title)|\(artist)" }

    func position(at date: Date = Date()) -> Double {
        guard isPlaying else { return elapsed }
        let value = elapsed + date.timeIntervalSince(timestamp)
        return duration > 0 ? min(max(value, 0), duration) : max(value, 0)
    }

    // MARK: - Источники

    private enum Source { case adapter, script(ScriptablePlayers.Player) }
    private var source: Source = .adapter

    private var process: Process?
    private var input: FileHandle?
    private var buffer = Data()
    private var stopping = false
    private var adapterFailures = 0
    private var adapterAlive = false
    private var adapterEmpty = true

    private let scripts = ScriptablePlayers()
    private var fallbackTimer: Timer?
    private var liveActivityWork: DispatchWorkItem?
    private var scriptArtworkTrack = ""
    /// Отложенная очистка: браузеры на мгновение присылают пустое состояние при переключении.
    private var clearWork: DispatchWorkItem?
    /// После нажатия ⏯ плеер ещё пару сотен миллисекунд присылает старое состояние —
    /// не даём кнопке мигать туда-обратно.
    private var expectedPlaying: Bool?
    private var expectedUntil = Date.distantPast

    init() {
        signal(SIGPIPE, SIG_IGN)
        launchAdapter()
        fallbackTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.pollFallback()
        }
    }

    func stop() {
        stopping = true
        process?.terminate()
    }

    // MARK: - Команды

    func togglePlayPause() {
        let now = Date()
        elapsed = position(at: now)
        timestamp = now
        withAnimation(.spring(response: 0.35, dampingFraction: 0.72)) { isPlaying.toggle() }
        expectedPlaying = isPlaying
        expectedUntil = now.addingTimeInterval(1.2)
        updateLiveActivity()
        send("toggle", script: .playPause)
    }

    func next() { manualSkip = true; send("next", script: .next) }
    func previous() { manualSkip = true; send("previous", script: .previous) }

    func toggleRepeat() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { repeatOne.toggle() }
        repeatTrackID = repeatOne ? trackID : nil
        repeatTimer?.invalidate()
        repeatTimer = nil
        guard repeatOne else { return }
        let t = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in self?.checkRepeat() }
        RunLoop.main.add(t, forMode: .common)
        repeatTimer = t
    }

    private var repeatTrackID: String?
    private var repeatTimer: Timer?
    private var manualSkip = false
    private var lastRepeatSeek = Date.distantPast

    private func checkRepeat() {
        guard repeatOne, isPlaying, duration > 3, trackID == repeatTrackID,
              Date().timeIntervalSince(lastRepeatSeek) > 2 else { return }
        if position() >= duration - 0.7 {
            lastRepeatSeek = Date()
            seek(to: 0)
        }
    }

    /// Плеер сам переключился на следующий трек раньше, чем мы успели перемотать, — возвращаемся.
    private func handleRepeatOnTrackChange() {
        guard repeatOne, let id = repeatTrackID else { return }
        if manualSkip {
            manualSkip = false
            repeatTrackID = trackID
        } else if trackID != id && Date().timeIntervalSince(lastRepeatSeek) > 2 {
            lastRepeatSeek = Date()
            send("previous", script: .previous)
        }
    }

    func seek(to seconds: Double) {
        elapsed = seconds
        timestamp = Date()
        send("seek \(seconds)", script: .seek(seconds))
    }

    func openSourceApp() {
        guard let bundleID, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: .init())
    }

    private func send(_ command: String, script: ScriptablePlayers.Command) {
        switch source {
        case .adapter:
            try? input?.write(contentsOf: Data((command + "\n").utf8))
        case .script(let player):
            scripts.perform(script, on: player)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in self?.pollFallback() }
        }
    }

    // MARK: - MediaRemote-адаптер

    private func launchAdapter() {
        guard let res = Bundle.main.resourceURL else { return }
        let script = res.appendingPathComponent("run.pl")
        let lib = res.appendingPathComponent("libIslandMedia.dylib")
        guard FileManager.default.fileExists(atPath: script.path),
              FileManager.default.fileExists(atPath: lib.path) else {
            NSLog("Media adapter not bundled; using AppleScript fallback only")
            return
        }

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        proc.arguments = [script.path, lib.path]
        let out = Pipe(), inp = Pipe()
        proc.standardOutput = out
        proc.standardInput = inp
        proc.standardError = FileHandle.nullDevice

        out.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty else { return }
            DispatchQueue.main.async { self?.consume(chunk) }
        }
        proc.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async { self?.adapterTerminated() }
        }

        do {
            try proc.run()
            process = proc
            input = inp.fileHandleForWriting
        } catch {
            NSLog("Failed to launch media adapter: \(error)")
        }
    }

    private func adapterTerminated() {
        adapterAlive = false
        adapterEmpty = true
        process = nil
        input = nil
        buffer.removeAll()
        guard !stopping else { return }
        adapterFailures += 1
        guard adapterFailures < 6 else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + Double(adapterFailures)) { [weak self] in
            self?.launchAdapter()
        }
    }

    private func consume(_ chunk: Data) {
        buffer.append(chunk)
        while let newline = buffer.firstIndex(of: 0x0A) {
            let line = buffer[buffer.startIndex..<newline]
            buffer.removeSubrange(buffer.startIndex...newline)
            guard let obj = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else { continue }
            handleAdapter(obj)
        }
    }

    private func handleAdapter(_ msg: [String: Any]) {
        switch msg["type"] as? String {
        case "ready":
            adapterAlive = true
            adapterFailures = 0
        case "error":
            adapterAlive = false
        case "state":
            adapterAlive = true
            if msg["empty"] as? Bool == true || (msg["title"] as? String ?? "").isEmpty {
                adapterEmpty = true
                if case .adapter = source { scheduleClear() }
                return
            }
            adapterEmpty = false
            source = .adapter
            cancelClear()

            var playing = msg["playing"] as? Bool ?? false
            if let expected = expectedPlaying, Date() < expectedUntil {
                if playing != expected { playing = expected } else { expectedPlaying = nil }
            }
            var elapsed = msg["elapsed"] as? Double ?? 0
            var stamp = Date()
            if let ts = msg["timestamp"] as? Double {
                stamp = Date(timeIntervalSince1970: ts)
            }
            // Если плеер не присылает скорость, но играет, считаем её равной 1.
            if let rate = msg["rate"] as? Double, rate == 0, playing {
                elapsed += Date().timeIntervalSince(stamp)
                stamp = Date()
            }

            let incomingID = "\(msg["title"] as? String ?? "")|\(msg["artist"] as? String ?? "")|\(msg["album"] as? String ?? "")"
            var artwork: ArtworkUpdate = .keep
            if msg["hasArtwork"] as? Bool == false {
                // Для того же трека обложка иногда пропадает на мгновение — оставляем старую.
                artwork = incomingID == trackID ? .keep : .clear
            } else if let b64 = msg["artwork"] as? String, let data = Data(base64Encoded: b64),
                      let image = NSImage(data: data) {
                artwork = .set(image)
            }

            apply(title: msg["title"] as? String ?? "",
                  artist: msg["artist"] as? String ?? "",
                  album: msg["album"] as? String ?? "",
                  duration: msg["duration"] as? Double ?? 0,
                  elapsed: elapsed, timestamp: stamp, playing: playing,
                  bundleID: (msg["parentBundle"] as? String) ?? (msg["bundle"] as? String),
                  artwork: artwork)
        default:
            break
        }
    }

    // MARK: - AppleScript-фолбэк

    private func pollFallback() {
        guard !adapterAlive || adapterEmpty else { return }
        guard let snap = scripts.poll() else {
            if case .script = source { scheduleClear() }
            return
        }
        cancelClear()
        source = .script(snap.player)
        var artwork: ArtworkUpdate = .keep
        let key = "\(snap.title)|\(snap.artist)"
        if key != scriptArtworkTrack {
            scriptArtworkTrack = key
            artwork = .clear
            scripts.loadArtwork(for: snap.player) { [weak self] image in
                guard let self, let image, self.scriptArtworkTrack == key else { return }
                self.setArtwork(image)
            }
        }
        apply(title: snap.title, artist: snap.artist, album: snap.album, duration: snap.duration,
              elapsed: snap.position, timestamp: Date(), playing: snap.playing,
              bundleID: snap.player.bundleID, artwork: artwork)
    }

    // MARK: - Применение состояния

    /// Для рендера снапшотов: подставить трек вручную.
    func debugSet(title: String, artist: String, album: String, duration: Double, elapsed: Double,
                  playing: Bool, artwork: NSImage?, bundleID: String?) {
        if title.isEmpty { clear(); showsLiveActivity = false; return }
        apply(title: title, artist: artist, album: album, duration: duration, elapsed: elapsed,
              timestamp: Date(), playing: playing, bundleID: bundleID,
              artwork: artwork.map(ArtworkUpdate.set) ?? .clear)
    }

    private enum ArtworkUpdate { case keep, clear, set(NSImage) }

    private func apply(title: String, artist: String, album: String, duration: Double,
                       elapsed: Double, timestamp: Date, playing: Bool, bundleID: String?,
                       artwork: ArtworkUpdate) {
        let newID = "\(title)|\(artist)|\(album)"
        let changed = newID != trackID

        withAnimation(changed ? .smooth(duration: 0.7) : .spring(response: 0.4, dampingFraction: 0.8)) {
            if changed {
                self.title = title
                self.artist = artist
                self.album = album
            }
            if abs(self.duration - duration) > 0.5 { self.duration = duration }
            self.isPlaying = playing
            self.bundleID = bundleID
        }
        // Позицию обновляем без анимации — иначе полоска прогресса «прыгает».
        self.elapsed = elapsed
        self.timestamp = timestamp
        switch artwork {
        case .keep: break
        case .clear: setArtwork(nil)
        case .set(let image): setArtwork(image)
        }
        updateLiveActivity()
        if changed && !title.isEmpty {
            handleRepeatOnTrackChange()
            onTrackChange?()
            // Через секунду смотрим на обложку: если её нет или она мелкая (браузеры присылают 300 px и меньше),
            // берём версию 1200 px из iTunes.
            let id = newID
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
                guard let self, self.trackID == id, Self.pixelWidth(self.artwork) < 512 else { return }
                RemoteImages.artwork(title: self.title, artist: self.artist) { [weak self] image in
                    guard let self, let image, self.trackID == id,
                          Self.pixelWidth(image) > Self.pixelWidth(self.artwork) else { return }
                    self.setArtwork(image)
                }
            }
        }
    }

    private static func pixelWidth(_ image: NSImage?) -> Int {
        guard let image else { return 0 }
        return image.representations.map(\.pixelsWide).max() ?? Int(image.size.width)
    }

    private func setArtwork(_ image: NSImage?) {
        let color = image.flatMap(ArtworkColor.accent(of:)) ?? .white
        let halo = image.flatMap(ArtworkColor.glow(of:))
        let crisp = image.map { ArtworkColor.displayCopy(of: $0) }
        withAnimation(.smooth(duration: 0.8)) {
            artwork = crisp
            accent = color
            glow = halo
        }
    }

    private func scheduleClear() {
        guard clearWork == nil, hasTrack else { return }
        let work = DispatchWorkItem { [weak self] in
            self?.clearWork = nil
            self?.clear()
            self?.source = .adapter
        }
        clearWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: work)
    }

    private func cancelClear() {
        clearWork?.cancel()
        clearWork = nil
    }

    private func clear() {
        guard hasTrack || isPlaying else { return }
        withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) {
            title = ""; artist = ""; album = ""
            duration = 0; elapsed = 0
            isPlaying = false
            bundleID = nil
        }
        setArtwork(nil)
        updateLiveActivity()
    }

    /// После паузы остров ещё несколько секунд показывает трек, потом прячет его.
    private func updateLiveActivity() {
        liveActivityWork?.cancel()
        if isPlaying && hasTrack {
            if !showsLiveActivity { withAnimation(IslandMetrics.spring) { showsLiveActivity = true } }
            return
        }
        guard showsLiveActivity else { return }
        let work = DispatchWorkItem { [weak self] in
            withAnimation(IslandMetrics.softSpring) { self?.showsLiveActivity = false }
        }
        liveActivityWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + (hasTrack ? 6 : 0), execute: work)
    }
}

// MARK: - Цвет обложки

enum ArtworkColor {
    private static let ciContext = CIContext(options: [.useSoftwareRenderer: false])

    /// Копия обложки 512×512 для показа. Уменьшаем заранее с качественной интерполяцией:
    /// SwiftUI при масштабировании большой картинки на лету даёт «мыло» и лесенку.
    static func displayCopy(of image: NSImage, side: Int = 512) -> NSImage {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return image }
        // Мелкие обложки не растягиваем — пусть масштабирует экран.
        guard cg.width > side || cg.height > side else { return image }
        let scale = CGFloat(side) / CGFloat(max(cg.width, cg.height))
        let w = Int((CGFloat(cg.width) * scale).rounded()), h = Int((CGFloat(cg.height) * scale).rounded())
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return image }
        ctx.interpolationQuality = .high
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        guard let out = ctx.makeImage() else { return image }
        // Размер в точках — половина пикселей, чтобы на Retina картинка шла 1:1.
        return NSImage(cgImage: out, size: NSSize(width: w / 2, height: h / 2))
    }

    /// Поле вокруг обложки в долях её стороны: свечение растекается на 5/8 стороны в каждую сторону.
    static let glowSpread: CGFloat = 0.625

    /// Обложка 64×64 в прозрачном поле 40 px, размытая по Гауссу: каждый край светит своим цветом
    /// и плавно уходит в ноль, без резких границ.
    static func glow(of image: NSImage) -> NSImage? {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let inner = 64, pad = 40, side = inner + pad * 2
        guard let ctx = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.interpolationQuality = .high
        ctx.draw(cg, in: CGRect(x: pad, y: pad, width: inner, height: inner))
        guard let padded = ctx.makeImage() else { return nil }
        let source = CIImage(cgImage: padded)
        let soft = source.applyingGaussianBlur(sigma: 12).cropped(to: source.extent)
            .applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 1.55, kCIInputBrightnessKey: 0.06])
            // Чуть усиливаем прозрачность, чтобы свечение было ярче и дальше растекалось.
            .applyingFilter("CIColorMatrix", parameters: ["inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1.6)])
        guard let out = ciContext.createCGImage(soft, from: source.extent) else { return nil }
        return NSImage(cgImage: out, size: NSSize(width: side, height: side))
    }

    /// Средний цвет обложки, подкрученный так, чтобы хорошо читаться на чёрном.
    static func accent(of image: NSImage) -> Color? {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        var pixel = [UInt8](repeating: 0, count: 4)
        guard let ctx = CGContext(data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.interpolationQuality = .medium
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        let base = NSColor(red: CGFloat(pixel[0]) / 255, green: CGFloat(pixel[1]) / 255,
                           blue: CGFloat(pixel[2]) / 255, alpha: 1)
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        base.usingColorSpace(.deviceRGB)?.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        let tuned = NSColor(hue: h, saturation: min(s * 1.35, 0.85), brightness: max(b, 0.78), alpha: 1)
        return Color(nsColor: tuned)
    }
}
