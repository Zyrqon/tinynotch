import Foundation
import AppKit
import Combine

private extension URLSession {
    /// Синхронная загрузка с таймаутом (вызывается только из фоновой очереди).
    func dataSync(_ request: URLRequest) -> Data? {
        var result: Data?
        let semaphore = DispatchSemaphore(value: 0)
        dataTask(with: request) { data, _, _ in
            result = data
            semaphore.signal()
        }.resume()
        _ = semaphore.wait(timeout: .now() + 12)
        return result
    }
}


/// Пак инструментов (аддон): JSON-файл со списком ToolID. Как аддоны в Blender:
/// базовая сборка несёт ядро, паки скачиваются с сайта и кладутся в папку паков.
struct ToolPack: Identifiable, Equatable, Codable {
    let id: String
    let name: String
    let version: String
    let author: String
    let tools: [String]

    static var packsDir: URL {
        let base = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/TinyNotch", isDirectory: true)
        let dir = base.appendingPathComponent("ToolPacks", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func loadAll() -> [ToolPack] {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: packsDir, includingPropertiesForKeys: nil) else { return [] }
        var out: [ToolPack] = []
        for f in files.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) where f.pathExtension == "json" {
            if let data = try? Data(contentsOf: f),
               let pack = try? JSONDecoder().decode(ToolPack.self, from: data) {
                out.append(pack)
            }
        }
        return out
    }

    /// Установить пак из скачанного JSON-файла.
    @discardableResult
    static func install(at url: URL) -> Bool {
        guard url.pathExtension == "json",
              let data = try? Data(contentsOf: url),
              let pack = try? JSONDecoder().decode(ToolPack.self, from: data) else { return false }
        let dest = packsDir.appendingPathComponent("\(pack.id).json")
        try? data.write(to: dest)
        return true
    }

    static func remove(_ id: String) {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: packsDir, includingPropertiesForKeys: nil) else { return }
        for f in files where f.pathExtension == "json" {
            if let data = try? Data(contentsOf: f),
               let pack = try? JSONDecoder().decode(ToolPack.self, from: data), pack.id == id {
                try? fm.removeItem(at: f)
            }
        }
    }
}

/// Менеджер паков: какие тулы включены в режиме «база», какие паки стоят.
final class ToolPackManager: ObservableObject {
    static let shared = ToolPackManager()
    static let siteURL = URL(string: "https://zyrqon.github.io/tinynotch/tools.html")!

    @Published var packs: [ToolPack] = []
    @Published var baseOnly: Bool {
        didSet { UserDefaults.standard.set(baseOnly, forKey: "tools.baseOnly") }
    }

    init() {
        baseOnly = UserDefaults.standard.object(forKey: "tools.baseOnly") as? Bool ?? false
        packs = ToolPack.loadAll()
    }

    var enabledIDs: Set<String> {
        var set = Self.baseIDs
        for pack in packs { set.formUnion(pack.tools) }
        return set
    }

    /// В полной сборке (тумблер «Все») включено всё; в режиме «База» — только база и паки.
    func isEnabled(_ tool: ToolID) -> Bool {
        !baseOnly || Self.baseIDs.contains(tool.rawValue)
    }

    /// Каким установленным паком закрывается тул (для подписи на замке).
    func pack(for tool: ToolID) -> ToolPack? {
        let raw = tool.rawValue
        return packs.first { $0.tools.contains(raw) }
    }

/// Зеркала для скачивания паков: GitHub Pages (открывается из РФ), затем Vercel, затем jsDelivr.
    static let packMirrors: [String] = [
        "https://zyrqon.github.io/tinynotch/packs",
        "https://tinynotch.vercel.app/packs",
        "https://cdn.jsdelivr.net/gh/Zyrqon/tinynotch@main/packs",
    ]

    /// Скачать пак с сайта в один клик. Результат приходит на главном потоке.
    func installFromWeb(id: String, completion: ((Bool) -> Void)? = nil) {
        guard !id.isEmpty else { completion?(false); return }
        let id = id
        DispatchQueue.global(qos: .userInitiated).async {
            let decoder = JSONDecoder()
            var done: ToolPack?
            for base in Self.packMirrors {
                guard let url = URL(string: "\(base)/\(id).json") else { continue }
                var request = URLRequest(url: url)
                request.timeoutInterval = 8
                guard let data = URLSession.shared.dataSync(request),
                      let pack = try? decoder.decode(ToolPack.self, from: data) else { continue }
                let dest = ToolPack.packsDir.appendingPathComponent("\(pack.id).json")
                try? data.write(to: dest)
                done = pack
                break
            }
            DispatchQueue.main.async {
                if done != nil { self.reload() }
                completion?(done != nil)
            }
        }
    }

    func install(from url: URL) {
        ToolPack.install(at: url)
        reload()
    }

    func remove(_ pack: ToolPack) {
        ToolPack.remove(pack.id)
        reload()
    }

    func reload() {
        packs = ToolPack.loadAll()
    }

    func openPacksFolder() {
        NSWorkspace.shared.open(ToolPack.packsDir)
    }

    func openSite() {
        NSWorkspace.shared.open(Self.siteURL)
    }

    /// База: Текст + Счёт (28 тулов). Остальные 72 приходят паками с сайта.
    static let baseIDs: Set<String> = [
        "stripFormat",
        "charCount",
        "caseConvert",
        "translit",
        "base64",
        "urlEncode",
        "jsonFormat",
        "sha256",
        "uuidGen",
        "passGen",
        "unixTime",
        "regexTest",
        "textDiff",
        "loremIpsum",
        "morse",
        "romanNumerals",
        "calculator",
        "unitConvert",
        "currencyConvert",
        "percentCalc",
        "loanCalc",
        "randomPick",
        "randomFromList",
        "qrGen",
        "colorPicker",
        "hexRgb",
        "paletteImg",
        "screenRuler"
    ]
}
