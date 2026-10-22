import SwiftUI
import AppKit
import AVFoundation
import Vision
import PDFKit

/// Куда складываются результаты тулов: ~/Downloads/Notchly Tools
enum ToolOutput {
    static var folder: URL {
        let url = URL(fileURLWithPath: NSHomeDirectory() + "/Downloads/Notchly Tools")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
    static func uniqueURL(name: String) -> URL {
        var index = 1
        var candidate = folder.appendingPathComponent(name)
        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        while FileManager.default.fileExists(atPath: candidate.path) {
            index += 1
            candidate = folder.appendingPathComponent("\(base) \(index).\(ext)")
        }
        return candidate
    }
    static func reveal(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}

// MARK: - 044/045 Скриншоты

struct ShotTool: View {
    let isArea: Bool
    @ViewState private var status = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(L(isArea ? "Выделить область" : "Выбрать окно")) { capture() }
                .buttonStyle(.bordered).controlSize(.small)
            Text(L("Нужен доступ к записи экрана в настройках macOS"))
                .font(.caption2).foregroundStyle(.secondary)
            Text(status).font(.caption)
        }
    }

    private func capture() {
        let url = ToolOutput.uniqueURL(name: "Снимок \(Int(Date().timeIntervalSince1970)).png")
        let mode = isArea ? "-i" : "-w"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = [mode, "-o", url.path]
        do {
            try process.run()
            status = L("Выдели на экране, файл упадёт в Downloads/Notchly Tools")
        } catch {
            status = L("Не запустился снимок экрана")
        }
    }
}

// MARK: - 046 OCR

struct OcrShotTool: View {
    @ViewState private var text = ""
    @ViewState private var hint = L("Перетащи картинку или скриншот сюда")

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(hint).font(.caption).foregroundStyle(.secondary)
            Text(text.isEmpty ? "—" : text)
                .font(.system(.caption, design: .monospaced))
                .frame(maxWidth: .infinity, minHeight: 80, alignment: .topLeading)
                .textSelection(.enabled)
            if !text.isEmpty {
                Button(L("Копировать")) { ToolClipboard.copy(text) }.buttonStyle(.bordered).controlSize(.small)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 90, alignment: .leading)
        .background(.quinary, in: RoundedRectangle(cornerRadius: 10))
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            guard let provider = providers.first else { return false }
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                DispatchQueue.main.async { hint = L("Распознаю…") }
                recognize(url)
            }
            return true
        }
    }

    private func recognize(_ url: URL) {
        let requestHandler = VNImageRequestHandler(url: url)
        let request = VNRecognizeTextRequest { request, _ in
            let lines = (request.results as? [VNRecognizedTextObservation])?
                .compactMap { $0.topCandidates(1).first?.string } ?? []
            DispatchQueue.main.async {
                text = lines.joined(separator: "\n")
                hint = text.isEmpty ? L("Текста не нашёл") : L("Готово")
            }
        }
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["ru-RU", "en-US"]
        DispatchQueue.global(qos: .userInitiated).async {
            try? requestHandler.perform([request])
        }
    }
}

// MARK: - 047/048 Запись звука и диктофон

struct MicRecordTool: View {
    @ViewState private var recorder: AVAudioRecorder?
    @ViewState private var isRecording = false
    @ViewState private var notes: [URL] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(isRecording ? L("Стоп") : L("Записать")) { toggle() }
                .buttonStyle(.bordered).controlSize(.small)
                .tint(isRecording ? .red : .primary)
            if isRecording { Text(L("Идёт запись…")).font(.caption).foregroundStyle(.red) }
            ForEach(notes, id: \.self) { note in
                HStack {
                    Text(note.lastPathComponent).font(.caption).lineLimit(1)
                    Spacer()
                    Button(L("Открыть")) { ToolOutput.reveal(note) }.buttonStyle(.bordered).controlSize(.mini)
                }
            }
        }
        .onAppear { reload() }
    }

    private func reload() {
        notes = (try? FileManager.default.contentsOfDirectory(
            at: ToolOutput.folder, includingPropertiesForKeys: nil))?
            .filter { $0.pathExtension == "m4a" }
            .sorted { $0.lastPathComponent > $1.lastPathComponent } ?? []
    }

    private func toggle() {
        if isRecording {
            recorder?.stop()
            recorder = nil
            isRecording = false
            reload()
            return
        }
        AVCaptureDevice.requestAccess(for: .audio) { granted in
            guard granted else { return }
            let url = ToolOutput.uniqueURL(name: "Заметка \(Int(Date().timeIntervalSince1970)).m4a")
            let settings: [String: Any] = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 44100,
                AVNumberOfChannelsKey: 1,
            ]
            DispatchQueue.main.async {
                recorder = try? AVAudioRecorder(url: url, settings: settings)
                recorder?.record()
                isRecording = recorder != nil
            }
        }
    }
}

// MARK: - 049 Конвертер картинок+

struct ImgConvertExtTool: View {
    @ViewState private var inputURL: URL?
    @ViewState private var format = "heic"
    @ViewState private var status = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker(L("Формат"), selection: $format) {
                Text("HEIC").tag("heic")
                Text("JPEG").tag("jpeg")
                Text("PNG").tag("png")
                Text("TIFF").tag("tiff")
            }.pickerStyle(.segmented)
            DropZone(hint: L("Перетащи картинку")) { url in
                inputURL = url
                convert(url)
            }
            Text(status).font(.caption)
        }
    }

    private func convert(_ url: URL) {
        let escaped = url.path.replacingOccurrences(of: "\"", with: "")
        let target = ToolOutput.uniqueURL(name: ((url.lastPathComponent as NSString).deletingPathExtension) + "." + format)
        let result = Shell.run("sips -s format \(format) \"\(escaped)\" --out \"\(target.path)\" 2>&1")
        status = FileManager.default.fileExists(atPath: target.path)
            ? L("Готово: ") + target.lastPathComponent
            : L("Не получилось: ") + result
    }
}

/// Общая зона перетаскивания для тулов.
struct DropZone: View {
    let hint: String
    let onFile: (URL) -> Void

    var body: some View {
        Text(hint)
            .font(.caption).foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: 60, alignment: .center)
            .background(.quinary, in: RoundedRectangle(cornerRadius: 10))
            .onDrop(of: [.fileURL], isTargeted: nil) { providers in
                guard let provider = providers.first else { return false }
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    guard let url else { return }
                    DispatchQueue.main.async { onFile(url) }
                }
                return true
            }
    }
}

// MARK: - 050-052 PDF: сжатие, слияние, разделение

struct PdfCompressTool: View {
    @ViewState private var status = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            DropZone(hint: L("Перетащи PDF")) { url in compress(url) }
            Text(status).font(.caption)
        }
    }

    private func compress(_ url: URL) {
        guard let document = PDFDocument(url: url) else { status = L("Не открыл PDF"); return }
        let target = ToolOutput.uniqueURL(name: ((url.lastPathComponent as NSString).deletingPathExtension) + ".compressed.pdf")
        let merged = PDFDocument()
        for index in 0..<document.pageCount {
            guard let page = document.page(at: index) else { continue }
            let bounds = page.bounds(for: .mediaBox)
            let scale: CGFloat = 1.5
            let size = CGSize(width: bounds.width * scale, height: bounds.height * scale)
            let image = NSImage(size: size)
            image.lockFocus()
            NSColor.white.setFill()
            NSBezierPath(rect: NSRect(origin: .zero, size: size)).fill()
            let context = NSGraphicsContext.current
            context?.cgContext.saveGState()
            context?.cgContext.scaleBy(x: scale, y: scale)
            page.draw(with: .mediaBox, to: context!.cgContext)
            context?.cgContext.restoreGState()
            image.unlockFocus()
            guard let tiff = image.tiffRepresentation,
                  let rep = NSBitmapImageRep(data: tiff),
                  let jpeg = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.55]) else { continue }
            if let newPage = PDFPage(image: NSImage(data: jpeg) ?? NSImage()) {
                merged.insert(newPage, at: merged.pageCount)
            }
        }
        merged.write(to: target)
        status = L("Готово: ") + target.lastPathComponent + " · " + String(document.pageCount) + " стр."
    }
}

struct PdfMergeTool: View {
    @ViewState private var urls: [URL] = []
    @ViewState private var status = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L("Перетащи несколько PDF (по одному или сразу)"))
                .font(.caption).foregroundStyle(.secondary)
            ForEach(urls, id: \.self) { Text($0.lastPathComponent).font(.caption2).lineLimit(1) }
            Button(L("Слить")) { merge() }.buttonStyle(.bordered).controlSize(.small).disabled(urls.count < 2)
            Text(status).font(.caption)
        }
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            for provider in providers {
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    guard let url, url.pathExtension.lowercased() == "pdf" else { return }
                    DispatchQueue.main.async { urls.append(url) }
                }
            }
            return true
        }
    }

    private func merge() {
        let merged = PDFDocument()
        for url in urls {
            guard let document = PDFDocument(url: url) else { continue }
            for index in 0..<document.pageCount {
                if let page = document.page(at: index) {
                    merged.insert(page, at: merged.pageCount)
                }
            }
        }
        let target = ToolOutput.uniqueURL(name: "Слитый.pdf")
        merged.write(to: target)
        status = L("Готово: ") + target.lastPathComponent
    }
}

struct PdfSplitTool: View {
    @ViewState private var status = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            DropZone(hint: L("Перетащи PDF — каждую страницу в отдельный файл")) { url in split(url) }
            Text(status).font(.caption)
        }
    }

    private func split(_ url: URL) {
        guard let document = PDFDocument(url: url) else { status = L("Не открыл PDF"); return }
        let base = ((url.lastPathComponent as NSString).deletingPathExtension)
        var count = 0
        for index in 0..<document.pageCount {
            guard let page = document.page(at: index) else { continue }
            let single = PDFDocument()
            single.insert(page, at: 0)
            let target = ToolOutput.uniqueURL(name: "\(base)-\(index + 1).pdf")
            single.write(to: target)
            count += 1
        }
        status = L("Готово: ") + "\(count)" + L(" файлов в Downloads/Notchly Tools")
    }
}

// MARK: - 053 Поворот картинки

struct ImgRotateTool: View {
    @ViewState private var picked: URL?
    @ViewState private var status = L("Перетащи картинку")

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Button(L("90° по часовой")) { apply("rotate 90") }
                Button(L("90° против")) { apply("rotate 270") }
                Button(L("Отразить")) { apply("flip horizontal") }
            }.buttonStyle(.bordered).controlSize(.small)
            DropZone(hint: L("Перетащи картинку")) { url in
                picked = url
                status = url.lastPathComponent
            }
            Text(status).font(.caption)
        }
    }

    private func apply(_ action: String) {
        guard let url = picked else { status = L("Сначала перетащи картинку"); return }
        let escaped = url.path.replacingOccurrences(of: "\"", with: "")
        let name = ((url.lastPathComponent as NSString).deletingPathExtension) + ".\(action.contains("flip") ? "flip" : "rot").png"
        let target = ToolOutput.uniqueURL(name: name)
        let result = Shell.run("sips \(action) \"\(escaped)\" --out \"\(target.path)\" 2>&1")
        status = FileManager.default.fileExists(atPath: target.path)
            ? L("Готово: ") + target.lastPathComponent
            : L("Не получилось: ") + result
    }
}

// MARK: - 054 Водяной знак

struct ImgWatermarkTool: View {
    @ViewState private var watermark = "© Islet"
    @ViewState private var status = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField(L("Текст водяного знака"), text: $watermark).textFieldStyle(.roundedBorder)
            DropZone(hint: L("Перетащи картинку")) { url in apply(url) }
            Text(status).font(.caption)
        }
    }

    private func apply(_ url: URL) {
        guard let image = NSImage(contentsOf: url) else { status = L("Не открыл картинку"); return }
        let size = image.size
        let target = ToolOutput.uniqueURL(name: ((url.lastPathComponent as NSString).deletingPathExtension) + ".wm.png")
        let marked = NSImage(size: size)
        marked.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: size))
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: size.height / 14),
            .foregroundColor: NSColor.white.withAlphaComponent(0.7),
        ]
        let string = NSAttributedString(string: watermark, attributes: attributes)
        let textSize = string.size()
        string.draw(at: NSPoint(x: size.width - textSize.width - size.width / 30,
                                y: size.height / 30))
        marked.unlockFocus()
        guard let tiff = marked.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else {
            status = L("Не получилось отрисовать"); return
        }
        try? png.write(to: target)
        status = L("Готово: ") + target.lastPathComponent
    }
}

// MARK: - 055 Скачивание видео

struct VideoDownloadTool: View {
    @ViewState private var link = ""
    @ViewState private var status = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ToolInOut(placeholder: L("Ссылка на видео"), input: $link)
            Button(L("Скачать")) { download() }.buttonStyle(.bordered).controlSize(.small)
            Text(status).font(.caption)
            Text(L("Нужен yt-dlp (ставится через brew install yt-dlp)"))
                .font(.caption2).foregroundStyle(.secondary)
        }
    }

    private func download() {
        let trimmed = link.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.contains("http") else { status = L("Нет ссылки"); return }
        let escaped = trimmed.replacingOccurrences(of: "\"", with: "")
        DispatchQueue.global(qos: .background).async {
            let result = Shell.run("yt-dlp -P \"\(ToolOutput.folder.path)\" \"\(escaped)\" 2>&1 | tail -2")
            DispatchQueue.main.async {
                status = result.isEmpty ? L("yt-dlp не найден") : result
            }
        }
        status = L("Качаю…")
    }
}

// MARK: - 056 Аудио из видео

struct VideoAudioTool: View {
    @ViewState private var status = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            DropZone(hint: L("Перетащи видео — вытащу звук в m4a")) { url in extract(url) }
            Text(status).font(.caption)
        }
    }

    private func extract(_ url: URL) {
        let asset = AVURLAsset(url: url)
        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            status = L("Экспорт недоступен"); return
        }
        let target = ToolOutput.uniqueURL(name: ((url.lastPathComponent as NSString).deletingPathExtension) + ".m4a")
        try? FileManager.default.removeItem(at: target)
        session.outputURL = target
        session.outputFileType = .m4a
        session.exportAsynchronously {
            DispatchQueue.main.async {
                status = session.status == .completed
                    ? L("Готово: ") + target.lastPathComponent
                    : L("Экспорт не удался")
            }
        }
        status = L("Извлекаю…")
    }
}

// MARK: - 057 GIF из видео

struct VideoGifTool: View {
    @ViewState private var seconds: Double = 3
    @ViewState private var status = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(L("Секунд"))
                Slider(value: $seconds, in: 1...10, step: 1)
                Text("\(Int(seconds))").font(.system(.caption, design: .monospaced))
            }
            DropZone(hint: L("Перетащи видео")) { url in makeGif(url) }
            Text(status).font(.caption)
        }
    }

    private func makeGif(_ url: URL) {
        let asset = AVURLAsset(url: url)
        let duration = CMTimeGetSeconds(asset.duration)
        let clip = min(duration, seconds)
        guard clip > 0.5 else { status = L("Не открыл видео"); return }
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        let fps = 10.0
        let frames = Int(clip * fps)
        let target = ToolOutput.uniqueURL(name: ((url.lastPathComponent as NSString).deletingPathExtension) + ".gif")
        guard let destination = CGImageDestinationCreateWithURL(target as CFURL, "com.compuserve.gif" as CFString, frames, nil) else {
            status = L("Не создал GIF"); return
        }
        let properties: CFDictionary = [kCGImagePropertyGIFDelayTime: 1.0 / fps] as CFDictionary
        var exported = 0
        for index in 0..<frames {
            let time = CMTime(seconds: Double(index) / fps, preferredTimescale: 600)
            guard let cgImage = try? generator.copyCGImage(at: time, actualTime: nil) else { continue }
            CGImageDestinationAddImage(destination, cgImage, properties)
            exported += 1
        }
        CGImageDestinationFinalize(destination)
        status = exported > 0 ? L("Готово: ") + target.lastPathComponent : L("Кадры не вытащились")
    }
}

// MARK: - 058 Сжатие видео

struct VideoCompressTool: View {
    @ViewState private var status = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            DropZone(hint: L("Перетащи видео — пережму в низкое качество")) { url in compress(url) }
            Text(status).font(.caption)
        }
    }

    private func compress(_ url: URL) {
        let asset = AVURLAsset(url: url)
        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetLowQuality) else {
            status = L("Экспорт недоступен"); return
        }
        let target = ToolOutput.uniqueURL(name: ((url.lastPathComponent as NSString).deletingPathExtension) + ".small.mp4")
        try? FileManager.default.removeItem(at: target)
        session.outputURL = target
        session.outputFileType = .mp4
        session.exportAsynchronously {
            DispatchQueue.main.async {
                status = session.status == .completed
                    ? L("Готово: ") + target.lastPathComponent
                    : L("Экспорт не удался")
            }
        }
        status = L("Жму…")
    }
}

// MARK: - 059 Пакетное переименование

struct BatchRenameTool: View {
    @ViewState private var prefix = "фото"
    @ViewState private var status = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField(L("Префикс"), text: $prefix).textFieldStyle(.roundedBorder)
            DropZone(hint: L("Перетащи папку — файлы внутри станут префикс-1, префикс-2…")) { url in rename(url) }
            Text(status).font(.caption)
        }
    }

    private func rename(_ folder: URL) {
        guard let contents = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) else {
            status = L("Не открыл папку"); return
        }
        let files = contents.filter { !$0.hasDirectoryPath }.sorted { $0.lastPathComponent < $1.lastPathComponent }
        var renamed = 0
        for (index, file) in files.enumerated() {
            let target = folder.appendingPathComponent("\(prefix)-\(index + 1)\(file.pathExtension.isEmpty ? "" : "." + file.pathExtension)")
            do {
                try FileManager.default.moveItem(at: file, to: target)
                renamed += 1
            } catch { continue }
        }
        status = L("Переименовано: ") + "\(renamed)"
    }
}
