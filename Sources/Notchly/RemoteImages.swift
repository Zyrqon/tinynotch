import AppKit

/// Картинки из интернета: иконки музыкальных сервисов и обложки треков из iTunes Search API.
/// Всё кэшируется в памяти, ответы — на главном потоке.
enum RemoteImages {
    private static var cache: [String: NSImage] = [:]
    private static var pending: [String: [(NSImage?) -> Void]] = [:]

    /// Иконка iOS-версии приложения по bundle id (App Store есть не во всех странах, поэтому пробуем несколько).
    static func appIcon(bundleID: String, completion: @escaping (NSImage?) -> Void) {
        load(key: "app:\(bundleID)", completion: completion) { done in
            lookup(bundleID: bundleID, countries: ["us", "ru"], done: done)
        }
    }

    /// Обложка трека в высоком разрешении (1200 px) из iTunes. Берём только результат,
    /// у которого совпадают исполнитель и название, — иначе лучше оставить обложку плеера.
    static func artwork(title: String, artist: String, completion: @escaping (NSImage?) -> Void) {
        let term = "\(artist) \(simplified(title))".trimmingCharacters(in: .whitespaces)
        guard !term.isEmpty else { return completion(nil) }
        load(key: "art:\(term.lowercased())", completion: completion) { done in
            var comps = URLComponents(string: "https://itunes.apple.com/search")!
            comps.queryItems = [.init(name: "term", value: term), .init(name: "entity", value: "song"),
                                .init(name: "limit", value: "8")]
            fetchJSON(comps.url!) { json in
                let results = json?["results"] as? [[String: Any]] ?? []
                let wantTitle = normalized(simplified(title)), wantArtist = normalized(artist)
                let match = results.first { item in
                    let t = normalized(simplified(item["trackName"] as? String ?? ""))
                    let a = normalized(item["artistName"] as? String ?? "")
                    let titleOK = !wantTitle.isEmpty && (t.contains(wantTitle) || wantTitle.contains(t))
                    let artistOK = wantArtist.isEmpty || a.contains(wantArtist) || wantArtist.contains(a)
                    return titleOK && artistOK
                }
                guard let small = match?["artworkUrl100"] as? String,
                      let url = URL(string: small.replacingOccurrences(of: "100x100bb", with: "1200x1200bb"))
                else { return done(nil) }
                fetchImage(url, done: done)
            }
        }
    }

    /// «Song (feat. X) - Remastered 2011» → «Song».
    private static func simplified(_ title: String) -> String {
        var t = title
        for sep in [" (", " [", " - ", " – "] {
            if let r = t.range(of: sep) { t = String(t[..<r.lowerBound]) }
        }
        return t
    }

    private static func normalized(_ s: String) -> String {
        s.lowercased().folding(options: .diacriticInsensitive, locale: nil)
            .filter { $0.isLetter || $0.isNumber }
    }

    // MARK: - Внутреннее

    private static func load(key: String, completion: @escaping (NSImage?) -> Void,
                             fetch: (@escaping (NSImage?) -> Void) -> Void) {
        if let cached = cache[key] { return completion(cached) }
        if pending[key] != nil { pending[key]?.append(completion); return }
        pending[key] = [completion]
        fetch { image in
            DispatchQueue.main.async {
                if let image { cache[key] = image }
                pending.removeValue(forKey: key)?.forEach { $0(image) }
            }
        }
    }

    private static func lookup(bundleID: String, countries: [String], done: @escaping (NSImage?) -> Void) {
        guard let country = countries.first else { return done(nil) }
        let url = URL(string: "https://itunes.apple.com/lookup?bundleId=\(bundleID)&country=\(country)")!
        fetchJSON(url) { json in
            let results = json?["results"] as? [[String: Any]]
            if let icon = results?.first?["artworkUrl512"] as? String, let iconURL = URL(string: icon) {
                fetchImage(iconURL, done: done)
            } else {
                lookup(bundleID: bundleID, countries: Array(countries.dropFirst()), done: done)
            }
        }
    }

    private static func fetchJSON(_ url: URL, done: @escaping ([String: Any]?) -> Void) {
        URLSession.shared.dataTask(with: url) { data, _, _ in
            done(data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] })
        }.resume()
    }

    private static func fetchImage(_ url: URL, done: @escaping (NSImage?) -> Void) {
        URLSession.shared.dataTask(with: url) { data, _, _ in
            done(data.flatMap(NSImage.init(data:)))
        }.resume()
    }
}
