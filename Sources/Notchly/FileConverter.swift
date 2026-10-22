import AppKit
import SwiftUI
import ImageIO

// MARK: - Конвертер файлов (по мотивам Tangerine)

/// Действия над файлами, которые показывает кольцо конвертера.
enum ConvertAction: CaseIterable, Identifiable, Equatable {
    case compress, resize, stripMeta
    case toJpeg, toPng, toHeic, toPdf, toZip
    case toMp4, toM4a
    case pdfToPng

    var id: String { name }

    /// Короткая подпись под кнопкой формата.
    var shortName: String {
        switch self {
        case .compress: return L("Сжать")
        case .resize: return L("Размер")
        case .stripMeta: return L("Мета")
        case .pdfToPng: return "PNG"
        default: return name
        }
    }

    /// Короткая подпись для центра кольца.
    var name: String {
        switch self {
        case .compress: return L("Сжать")
        case .resize: return L("Уменьшить размер")
        case .stripMeta: return L("Убрать метаданные")
        case .toJpeg: return "JPEG"
        case .toPng: return "PNG"
        case .toHeic: return "HEIC"
        case .toPdf: return "PDF"
        case .toZip: return "ZIP"
        case .toMp4: return "MP4"
        case .toM4a: return "M4A"
        case .pdfToPng: return L("PDF в картинки")
        }
    }

    var icon: String {
        switch self {
        case .compress: return "arrow.down.right.and.arrow.up.left"
        case .resize: return "arrow.up.left.and.arrow.down.right"
        case .stripMeta: return "eye.slash"
        case .toJpeg, .toPng, .toHeic: return "photo"
        case .toPdf: return "doc.richtext"
        case .toZip: return "doc.zipper"
        case .toMp4: return "film"
        case .toM4a: return "waveform"
        case .pdfToPng: return "photo.on.rectangle.angled"
        }
    }
}

enum FileKind: Equatable {
    case image, pdf, video, audio, other
}

/// Принимает файлы, брошенные на остров, и конвертирует их локально:
/// sips для картинок, avconvert для видео/аудио, ImageIO и CoreGraphics для
/// метаданных и PDF, ditto для архивов. Всё встроенными средствами macOS,
/// ничего никуда не выгружается.
final class FileConverterModel: ObservableObject {
    @Published var isOpen = false
    @Published var files: [URL] = []
    @Published var isRunning = false
    @Published var statusText = ""

    /// Готово: карточка-уведомление с итогом (подставляет IslandModel).
    var onDone: ((String) -> Void)?
    /// Кнопка «На полку»: файлы уходят на Полку без конвертации.
    var onSendToShelf: (([URL]) -> Void)?

    /// Первый дроп открывает панель, докинутые следом файлы добавляются к ней же.
    func receive(_ urls: [URL]) {
        if isOpen {
            files.append(contentsOf: urls)
        } else {
            files = urls
            statusText = ""
            isOpen = true
        }
    }

    func close() {
        isOpen = false
        files = []
        statusText = ""
    }

    func sendToShelf() {
        let urls = files
        close()
        onSendToShelf?(urls)
    }

    // MARK: Какие действия показывать

    var availableActions: [ConvertAction] {
        guard !files.isEmpty else { return [] }
        let kinds = Set(files.map { Self.kind(of: $0) })
        // Смешанные типы или файлы без известных действий — только в ZIP.
        guard kinds.count == 1, let kind = kinds.first else { return [.toZip] }
        switch kind {
        case .image:
            var actions: [ConvertAction] = [.compress, .resize, .toPdf, .stripMeta]
            let exts = Set(files.map { $0.pathExtension.lowercased() })
            if exts.count == 1, let ext = exts.first {
                if ext != "jpg" && ext != "jpeg" { actions.insert(.toJpeg, at: 2) }
                if ext != "png" { actions.insert(.toPng, at: 2) }
                if ext != "heic" && ext != "heif" { actions.insert(.toHeic, at: 2) }
            } else {
                actions.insert(contentsOf: [.toJpeg, .toPng, .toHeic], at: 2)
            }
            return actions
        case .pdf: return [.pdfToPng, .toZip]
        case .video: return [.toMp4, .toM4a, .toZip]
        case .audio: return [.toM4a, .toZip]
        case .other: return [.toZip]
        }
    }

    static func kind(of url: URL) -> FileKind {
        let ext = url.pathExtension.lowercased()
        if ["jpg", "jpeg", "png", "heic", "heif", "tif", "tiff", "gif", "bmp", "webp"].contains(ext) { return .image }
        if ext == "pdf" { return .pdf }
        if ["mp4", "mov", "m4v", "avi", "mkv", "webm"].contains(ext) { return .video }
        if ["mp3", "wav", "m4a", "aac", "flac", "ogg", "aiff", "aif"].contains(ext) { return .audio }
        return .other
    }

    // MARK: Запуск

    func run(_ action: ConvertAction) {
        guard !isRunning, !files.isEmpty else { return }
        isRunning = true
        let work = files
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            var ok = 0, fail = 0
            var outs: [URL] = []
            if action == .toPdf && work.count > 1 {
                self.setStatus(L("Собираю PDF…"))
                if let pdf = self.imagesToPdf(work) { ok = 1; outs.append(pdf) } else { fail = 1 }
            } else if action == .pdfToPng {
                for url in work {
                    self.setStatus(url.lastPathComponent)
                    let pages = self.pdfToPng(url)
                    outs.append(contentsOf: pages)
                    if pages.isEmpty { fail += 1 } else { ok += pages.count }
                }
            } else {
                for (i, url) in work.enumerated() {
                    self.setStatus(L("Файл \(i + 1) из \(work.count): ") + url.lastPathComponent)
                    if let out = self.process(url, action) { ok += 1; outs.append(out) } else { fail += 1 }
                }
            }
            DispatchQueue.main.async {
                self.isRunning = false
                self.onDone?(self.summary(ok: ok, fail: fail, results: outs))
                self.close()
            }
        }
    }

    private func setStatus(_ text: String) {
        DispatchQueue.main.async { self.statusText = text }
    }

    private func summary(ok: Int, fail: Int, results: [URL]) -> String {
        let folder = results.first?.deletingLastPathComponent().path ?? ""
        if fail == 0 { return L("Готово: \(ok). Папка: \(folder)") }
        return L("Готово: \(ok), не удалось: \(fail). Папка: \(folder)")
    }

    private func process(_ url: URL, _ action: ConvertAction) -> URL? {
        switch action {
        case .toJpeg:
            let dst = unique(url, ext: "jpg")
            return runTool("/usr/bin/sips", ["-s", "format", "jpeg", url.path, "--out", dst.path]) ? dst : nil
        case .toPng:
            let dst = unique(url, ext: "png")
            return runTool("/usr/bin/sips", ["-s", "format", "png", url.path, "--out", dst.path]) ? dst : nil
        case .toHeic:
            let dst = unique(url, ext: "heic")
            return runTool("/usr/bin/sips", ["-s", "format", "heic", url.path, "--out", dst.path]) ? dst : nil
        case .resize:
            let dst = unique(url, ext: url.pathExtension.lowercased(), suffix: ".small")
            return runTool("/usr/bin/sips", ["-Z", "1280", url.path, "--out", dst.path]) ? dst : nil
        case .compress:
            let ext = url.pathExtension.lowercased()
            if ["jpg", "jpeg", "heic", "heif", "tif", "tiff"].contains(ext) {
                let dst = unique(url, ext: ext, suffix: ".min")
                return runTool("/usr/bin/sips", ["-s", "formatOptions", "65", url.path, "--out", dst.path]) ? dst : nil
            }
            let dst = unique(url, ext: "jpg", suffix: ".min")
            return runTool("/usr/bin/sips", ["-s", "format", "jpeg", "-s", "formatOptions", "75", url.path, "--out", dst.path]) ? dst : nil
        case .stripMeta:
            let dst = unique(url, ext: url.pathExtension.lowercased(), suffix: ".clean")
            return stripMetadata(url, dst: dst) ? dst : nil
        case .toPdf:
            return imagesToPdf([url])
        case .pdfToPng:
            return pdfToPng(url).first
        case .toZip:
            let dst = unique(url, ext: "zip")
            return runTool("/usr/bin/ditto", ["-c", "-k", url.path, dst.path]) ? dst : nil
        case .toMp4:
            let dst = unique(url, ext: "mp4")
            return runTool("/usr/bin/avconvert", ["--preset", "Preset1280x720", "--source", url.path, "--output", dst.path]) ? dst : nil
        case .toM4a:
            let dst = unique(url, ext: "m4a")
            return runTool("/usr/bin/avconvert", ["--preset", "PresetHighestQualityAudio", "--source", url.path, "--output", dst.path]) ? dst : nil
        }
    }

    // MARK: Инструменты

    @discardableResult
    private func runTool(_ path: String, _ args: [String]) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = args
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    /// Имя результата рядом с оригиналом: Page.jpg → Page.min.jpg, при занятости → Page.min-2.jpg.
    private func unique(_ url: URL, ext: String, suffix: String = "") -> URL {
        let stem = url.deletingPathExtension().lastPathComponent
        let dir = url.deletingLastPathComponent()
        var candidate = dir.appendingPathComponent(stem + suffix + "." + ext)
        var n = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = dir.appendingPathComponent("\(stem)\(suffix)-\(n).\(ext)")
            n += 1
        }
        return candidate
    }

    /// Пересохранение картинки без EXIF и прочих метаданных: свойства не переносятся вовсе.
    private func stripMetadata(_ src: URL, dst: URL) -> Bool {
        guard let source = CGImageSourceCreateWithURL(src as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return false }
        let uti = CGImageSourceGetType(source) ?? ("public.jpeg" as CFString)
        guard let dest = CGImageDestinationCreateWithURL(dst as CFURL, uti, 1, nil) else { return false }
        CGImageDestinationAddImage(dest, image, nil)
        return CGImageDestinationFinalize(dest)
    }

    /// Картинки в PDF: одна картинка — одна страница, размер страницы = размер картинки в @2x.
    private func imagesToPdf(_ urls: [URL]) -> URL? {
        guard let first = urls.first else { return nil }
        let dst = unique(first, ext: "pdf")
        guard let consumer = CGDataConsumer(url: dst as CFURL) else { return nil }
        var defaultBox = CGRect(x: 0, y: 0, width: 595, height: 842)
        guard let context = CGContext(consumer: consumer, mediaBox: &defaultBox, nil) else { return nil }
        var pages = 0
        for url in urls {
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { continue }
            let width = CGFloat(image.width) / 2.0
            let height = CGFloat(image.height) / 2.0
            guard width > 1, height > 1 else { continue }
            let box = CGRect(x: 0, y: 0, width: width, height: height)
            context.beginPDFPage([kCGPDFContextMediaBox: NSValue(rect: box)] as CFDictionary)
            context.draw(image, in: box)
            context.endPDFPage()
            pages += 1
        }
        guard pages > 0 else { return nil }
        context.closePDF()
        return dst
    }

    /// Страницы PDF в PNG (до 50 страниц, масштаб 2x).
    private func pdfToPng(_ src: URL) -> [URL] {
        guard let document = CGPDFDocument(src as CFURL) else { return [] }
        let count = min(document.numberOfPages, 50)
        guard count > 0 else { return [] }
        var outs: [URL] = []
        for i in 1...count {
            guard let page = document.page(at: i) else { continue }
            let box = page.getBoxRect(.mediaBox)
            let scale: CGFloat = 2
            let width = max(Int(box.width * scale), 1)
            let height = max(Int(box.height * scale), 1)
            guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
                  let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                          bytesPerRow: 0, space: colorSpace,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { continue }
            context.setFillColor(CGColor(gray: 1.0, alpha: 1.0))
            context.fill(CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)))
            context.scaleBy(x: scale, y: scale)
            context.drawPDFPage(page)
            guard let image = context.makeImage() else { continue }
            let dst = unique(src, ext: "png", suffix: String(format: ".page%d", i))
            guard let dest = CGImageDestinationCreateWithURL(dst as CFURL, "public.png" as CFString, 1, nil) else { continue }
            CGImageDestinationAddImage(dest, image, nil)
            if CGImageDestinationFinalize(dest) { outs.append(dst) }
        }
        return outs
    }
}

// MARK: - Панель конвертера на острове

/// Сектор кольца: многоугольник по явной формуле угла, чтобы иконки и клик
/// гарантированно совпадали с нарисованным сектором.
struct WedgeShape: Shape {
    var startDeg: Double
    var endDeg: Double

    static func point(center: CGPoint, radius: CGFloat, deg: Double) -> CGPoint {
        let rad = deg * .pi / 180
        return CGPoint(x: center.x + radius * CGFloat(cos(rad)), y: center.y + radius * CGFloat(sin(rad)))
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2 - 1
        path.move(to: center)
        let steps = 28
        for step in 0...steps {
            let t = Double(step) / Double(steps)
            let deg = startDeg + (endDeg - startDeg) * t
            path.addLine(to: Self.point(center: center, radius: radius, deg: deg))
        }
        path.closeSubpath()
        return path
    }
}

struct ConverterPanelView: View {
    @ObservedObject var model: FileConverterModel
    @ObservedObject var settings: AppSettings

    var body: some View {
        VStack(spacing: 2) {
            HStack(spacing: 8) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(settings.accent)
                Text(model.files.count == 1 ? model.files[0].lastPathComponent : L("Файлов: \(model.files.count)"))
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Button {
                    model.sendToShelf()
                } label: {
                    Text(L("На полку"))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .frame(minHeight: 26)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Button {
                    model.close()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 26, height: 26)
                        .background(Circle().fill(Color.white.opacity(0.10)))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.top, 6)

            if model.isRunning {
                VStack(spacing: 6) {
                    Spacer()
                    ProgressView().controlSize(.small)
                    Text(model.statusText)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer()
                }
            } else if model.files.isEmpty {
                VStack(spacing: 6) {
                    Spacer()
                    Image(systemName: "arrow.down.doc")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(.tertiary)
                    Text(L("Перетащи файлы на остров"))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            } else {
                HStack(spacing: 16) {
                    ForEach(model.availableActions) { action in
                        Button {
                            model.run(action)
                        } label: {
                            VStack(spacing: 4) {
                                Circle()
                                    .fill(Color.white.opacity(0.08))
                                    .overlay(
                                        Circle().strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
                                    )
                                    .frame(width: 42, height: 42)
                                    .overlay(
                                        Image(systemName: action.icon)
                                            .font(.system(size: 15, weight: .medium))
                                            .foregroundStyle(settings.accent)
                                    )
                                    .contentShape(Circle())
                                Text(action.shortName)
                                    .font(.system(size: 9, weight: .semibold))
                                    .foregroundStyle(.white.opacity(0.9))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.8)
                                    .frame(width: 52)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.bottom, 6)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(settings.islandBackground)
    }

}
