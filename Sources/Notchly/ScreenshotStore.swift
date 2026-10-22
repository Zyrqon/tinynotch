import AppKit
import CryptoKit
import SwiftUI

struct Screenshot: Identifiable, Codable, Equatable {
    var id = UUID()
    /// Имя файла внутри папки снимков — оно же имя при перетаскивании.
    var fileName: String
    var date: Date
    var width: Int
    var height: Int
    var bytes: Int
    /// SHA-256 содержимого: один и тот же снимок не сохраняем дважды.
    var digest: String
    /// Своё название вместо времени. От него же зависит имя файла при перетаскивании.
    var title: String?
}

/// Снимки экрана и скопированные картинки. Лежат несколько дней (по умолчанию 3) в
/// ~/Library/Application Support/Notchly/Screenshots с правами только для владельца.
/// Картинки тяжёлые, поэтому хранится не больше `maxItems` штук.
final class ScreenshotStore: ObservableObject {
    @Published private(set) var items: [Screenshot] = []

    static let retentionOptions = [1, 2, 3, 7]
    static let maxItems = 40
    /// Больше этого не берём: это уже не снимок, а что-то огромное.
    static let maxBytes = 40 * 1024 * 1024

    var retentionDays: Int {
        get { persistent ? (UserDefaults.standard.object(forKey: "screenshots.retentionDays") as? Int ?? 3) : 3 }
        set {
            objectWillChange.send()
            if persistent { UserDefaults.standard.set(newValue, forKey: "screenshots.retentionDays") }
            prune()
        }
    }

    var totalBytes: Int { items.reduce(0) { $0 + $1.bytes } }

    private let persistent: Bool
    var isPersistent: Bool { persistent }
    private var thumbnails: [UUID: NSImage] = [:]
    /// Для снапшотов: картинки только в памяти.
    private var memory: [UUID: Data] = [:]
    private var pruneTimer: Timer?

    static let directory: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Notchly/Screenshots", isDirectory: true)
        return base
    }()
    private static var indexURL: URL { directory.appendingPathComponent("index.json") }

    init(persistent: Bool = true) {
        self.persistent = persistent
        guard persistent else { return }
        let fm = FileManager.default
        try? fm.createDirectory(at: Self.directory, withIntermediateDirectories: true,
                                attributes: [.posixPermissions: 0o700])
        try? fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: Self.directory.path)
        if let data = try? Data(contentsOf: Self.indexURL),
           let saved = try? JSONDecoder().decode([Screenshot].self, from: data) {
            // Файл могли удалить руками — такие записи не показываем.
            items = saved.filter { fm.fileExists(atPath: url(for: $0).path) }
        }
        prune()
        pruneTimer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in self?.prune() }
    }

    func url(for shot: Screenshot) -> URL { Self.directory.appendingPathComponent(shot.fileName) }

    func data(for shot: Screenshot) -> Data? {
        memory[shot.id] ?? (try? Data(contentsOf: url(for: shot)))
    }

    func image(for shot: Screenshot) -> NSImage? { data(for: shot).flatMap(NSImage.init(data:)) }

    /// Уменьшенная копия для сетки — полноразмерные снимки в памяти не держим.
    func thumbnail(for shot: Screenshot) -> NSImage? {
        if let cached = thumbnails[shot.id] { return cached }
        guard let image = image(for: shot) else { return nil }
        let width: CGFloat = 320
        let scale = min(1, width / max(image.size.width, 1))
        let size = NSSize(width: image.size.width * scale, height: image.size.height * scale)
        let thumb = NSImage(size: size, flipped: false) { rect in
            image.draw(in: rect, from: .zero, operation: .copy, fraction: 1)
            return true
        }
        thumbnails[shot.id] = thumb
        return thumb
    }

    // MARK: - Добавление

    /// Картинка из буфера обмена: PNG, если есть, иначе TIFF, пересжатый в PNG.
    @discardableResult
    func add(pasteboard: NSPasteboard) -> Bool {
        if let png = pasteboard.data(forType: .png) { return add(png: png) }
        if let tiff = pasteboard.data(forType: .tiff), tiff.count < Self.maxBytes * 2,
           let rep = NSBitmapImageRep(data: tiff), let png = rep.representation(using: .png, properties: [:]) {
            return add(png: png)
        }
        return false
    }

    /// Снимок, который macOS сохранила файлом.
    func add(fileURL: URL) {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let data = try? Data(contentsOf: fileURL) else { return }
            let date = (try? fileURL.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? Date()
            DispatchQueue.main.async { self?.add(png: data, date: date) }
        }
    }

    @discardableResult
    func add(png raw: Data, date: Date = Date()) -> Bool {
        guard raw.count <= Self.maxBytes, let rep = NSBitmapImageRep(data: raw) else { return false }
        // Снимки бывают и в JPEG или HEIC (настройка screencapture) — храним всё одинаково, в PNG.
        let isPNG = raw.starts(with: [0x89, 0x50, 0x4E, 0x47])
        guard let data = isPNG ? raw : rep.representation(using: .png, properties: [:]) else { return false }
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        if let existing = items.firstIndex(where: { $0.digest == digest }) {
            // Уже есть — просто поднимаем наверх.
            var shot = items.remove(at: existing)
            shot.date = date
            withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { items.insert(shot, at: 0) }
            saveIndex()
            return true
        }
        let shot = Screenshot(fileName: uniqueName(for: date), date: date,
                              width: rep.pixelsWide, height: rep.pixelsHigh, bytes: data.count, digest: digest)
        if persistent {
            let url = url(for: shot)
            guard (try? data.write(to: url, options: .atomic)) != nil else { return false }
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        } else {
            memory[shot.id] = data
        }
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
            // Новые — первыми (снимок с диска может прийти позже, чем более свежий из буфера).
            items.insert(shot, at: items.firstIndex { $0.date < date } ?? items.endIndex)
        }
        trimToLimit()
        saveIndex()
        return true
    }

    // MARK: - Название

    /// Переименовать снимок: меняется и подпись, и имя файла (его видно, когда снимок перетаскивают).
    /// Пустое название возвращает подпись со временем.
    func rename(_ shot: Screenshot, to title: String) {
        guard let i = items.firstIndex(where: { $0.id == shot.id }) else { return }
        let clean = String(title.trimmingCharacters(in: .whitespacesAndNewlines).prefix(80))
        items[i].title = clean.isEmpty ? nil : clean
        if !clean.isEmpty {
            let safe = clean.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
            var name = safe + ".png"
            var n = 2
            while items.contains(where: { $0.id != shot.id && $0.fileName == name })
                    || (persistent && name != shot.fileName
                        && FileManager.default.fileExists(atPath: Self.directory.appendingPathComponent(name).path)) {
                name = "\(safe) (\(n)).png"
                n += 1
            }
            if name != shot.fileName {
                if persistent {
                    let from = url(for: shot), to = Self.directory.appendingPathComponent(name)
                    if (try? FileManager.default.moveItem(at: from, to: to)) != nil { items[i].fileName = name }
                } else {
                    items[i].fileName = name
                }
            }
        }
        saveIndex()
    }

    // MARK: - Удаление

    func remove(_ shot: Screenshot) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { items.removeAll { $0.id == shot.id } }
        deleteFile(shot)
        saveIndex()
    }

    func clear() {
        let all = items
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { items.removeAll() }
        all.forEach(deleteFile)
        saveIndex()
    }

    private func prune() {
        let cutoff = Date().addingTimeInterval(-Double(retentionDays) * 86_400)
        let old = items.filter { $0.date < cutoff }
        guard !old.isEmpty else { return }
        items.removeAll { $0.date < cutoff }
        old.forEach(deleteFile)
        saveIndex()
    }

    private func trimToLimit() {
        guard items.count > Self.maxItems else { return }
        let extra = Array(items[Self.maxItems...])
        items.removeLast(items.count - Self.maxItems)
        extra.forEach(deleteFile)
    }

    private func deleteFile(_ shot: Screenshot) {
        thumbnails[shot.id] = nil
        memory[shot.id] = nil
        guard persistent else { return }
        try? FileManager.default.removeItem(at: url(for: shot))
    }

    private func saveIndex() {
        guard persistent, let data = try? JSONEncoder().encode(items) else { return }
        try? data.write(to: Self.indexURL, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: Self.indexURL.path)
    }

    /// «Снимок 26.09 в 10.12.34.png» — понятное имя для перетаскивания и сохранения.
    private func uniqueName(for date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = Loc.isRussian ? "dd.MM 'в' HH.mm.ss" : "MM-dd 'at' HH.mm.ss"
        let base = L("Снимок %@", "\(f.string(from: date))")
        var name = base + ".png"
        var n = 2
        while items.contains(where: { $0.fileName == name })
                || (persistent && FileManager.default.fileExists(atPath: Self.directory.appendingPathComponent(name).path)) {
            name = "\(base) (\(n)).png"
            n += 1
        }
        return name
    }

    // MARK: - Действия

    /// Положить снимок в буфер обмена: как картинку (вставится в чат или документ) и как файл (в Finder).
    func write(_ shot: Screenshot, to pasteboard: NSPasteboard) {
        guard let data = data(for: shot) else { return }
        pasteboard.clearContents()
        let item = NSPasteboardItem()
        item.setData(data, forType: .png)
        if let tiff = NSImage(data: data)?.tiffRepresentation { item.setData(tiff, forType: .tiff) }
        if persistent { item.setString(url(for: shot).absoluteString, forType: .fileURL) }
        pasteboard.writeObjects([item])
    }

    /// Сохранить копию снимка туда, куда выберет пользователь.
    func saveCopy(_ shot: Screenshot) {
        guard let data = data(for: shot) else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = shot.fileName
        panel.allowedContentTypes = [.png]
        panel.directoryURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
        NSApp.activate(ignoringOtherApps: true)
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            try? data.write(to: url, options: .atomic)
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
    }

    // MARK: - Снапшоты

    func debugAdd(_ image: NSImage, date: Date) {
        guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return }
        add(png: png, date: date)
    }
}

/// Следит за снимками экрана, которые macOS сохраняет файлами (по умолчанию — на рабочий стол).
/// Ищет их через Spotlight (признак kMDItemIsScreenCapture), поэтому папку не сканирует.
/// Прочитать файл на рабочем столе можно только с разрешения — macOS спросит его при первом снимке.
final class ScreenshotFileWatcher {
    var onNew: ((URL) -> Void)?
    private var query: NSMetadataQuery?
    private var observer: NSObjectProtocol?

    var isRunning: Bool { query != nil }

    func start() {
        guard query == nil else { return }
        let query = NSMetadataQuery()
        query.predicate = NSPredicate(format: "kMDItemIsScreenCapture == 1 AND kMDItemFSCreationDate >= %@",
                                      Date() as NSDate)
        query.searchScopes = [NSMetadataQueryUserHomeScope]
        observer = NotificationCenter.default.addObserver(forName: .NSMetadataQueryDidUpdate, object: query,
                                                          queue: .main) { [weak self] note in
            let added = note.userInfo?[NSMetadataQueryUpdateAddedItemsKey] as? [NSMetadataItem] ?? []
            for item in added {
                guard let path = item.value(forAttribute: NSMetadataItemPathKey) as? String else { continue }
                // Файл может ещё дописываться — берём его чуть позже.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { self?.onNew?(URL(fileURLWithPath: path)) }
            }
        }
        query.start()
        self.query = query
    }

    func stop() {
        query?.stop()
        query = nil
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
    }
}
