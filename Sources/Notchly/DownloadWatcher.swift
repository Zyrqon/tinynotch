import Foundation

/// Завершённые загрузки: следит за недокачанными файлами в «Загрузках» и
/// выносит карточку, когда браузер их докачал (Safari/Chrome/Firefox).
final class DownloadWatcher {
    var onDone: ((String, Int64) -> Void)?
    private var timer: Timer?
    /// Имя частично скачанного файла → последний замеченный размер.
    private var partials: [String: Int64] = [:]
    private let dir = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]

    func start() {
        scan()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.scan() }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private static let partialExts: Set<String> = ["download", "crdownload", "part", "aria2", "partial"]

    private func scan() {
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.fileSizeKey]) else { return }
        var seen: Set<String> = []
        for url in items {
            guard Self.partialExts.contains(url.pathExtension.lowercased()) else { continue }
            seen.insert(url.lastPathComponent)
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize.map { Int64($0) } ?? 0
            partials[url.lastPathComponent] = size
        }
        for name in partials.keys where !seen.contains(name) {
            partials.removeValue(forKey: name)
            if let (path, bytes) = completed(matching: name) {
                onDone?(path, bytes)
            }
        }
    }

    /// «file.pdf.crdownload» → «file.pdf»; «X.download» (папка Safari) → самый свежий «X.*».
    private func completed(matching partialName: String) -> (String, Int64)? {
        let stem = (partialName as NSString).deletingPathExtension
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey]) else { return nil }
        var best: (String, Date, Int64)?
        for url in items where !Self.partialExts.contains(url.pathExtension.lowercased()) {
            guard url.lastPathComponent.hasPrefix(stem) else { continue }
            let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            if best == nil || date > best!.1 {
                let bytes = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize.map { Int64($0) } ?? 0
                best = (url.lastPathComponent, date, bytes)
            }
        }
        guard let hit = best else { return nil }
        return (dir.appendingPathComponent(hit.0).path, hit.2)
    }
}
