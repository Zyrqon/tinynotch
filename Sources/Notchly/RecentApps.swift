import AppKit

/// Недавно запущенные приложения: для вкладки «Программы».
final class RecentApps: ObservableObject {
    struct Entry: Codable, Equatable, Identifiable {
        let bundleID: String
        let name: String
        var last: Date
        var id: String { bundleID }
    }

    @Published private(set) var entries: [Entry] = []
    private var observer: NSObjectProtocol?

    init() {
        if let data = UserDefaults.standard.data(forKey: "recent.apps"),
           let list = try? JSONDecoder().decode([Entry].self, from: data) {
            entries = list
        }
    }

    func start() {
        let center = NSWorkspace.shared.notificationCenter
        observer = center.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  let id = app.bundleIdentifier, !id.hasPrefix("com.apple.") else { return }
            self?.touch(bundleID: id, name: app.localizedName ?? id)
        }
    }

    func stop() {
        if let observer { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        observer = nil
    }

    private func touch(bundleID: String, name: String) {
        entries.removeAll { $0.bundleID == bundleID }
        entries.insert(Entry(bundleID: bundleID, name: name, last: Date()), at: 0)
        if entries.count > 12 { entries = Array(entries.prefix(12)) }
        if let data = try? JSONEncoder().encode(entries) {
            UserDefaults.standard.set(data, forKey: "recent.apps")
        }
    }

    func appURL(for entry: Entry) -> URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: entry.bundleID)
    }
}
