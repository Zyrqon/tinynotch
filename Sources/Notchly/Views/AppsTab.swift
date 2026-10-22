import SwiftUI

/// Вкладка «Программы»: пара букв → приложение, плюс последние запущенные.
struct AppsTab: View {
    @ObservedObject var model: IslandModel
    @ObservedObject private var recents: RecentApps
    @ViewState private var query = ""
    @ViewState private var installed: [AppEntry] = []
    @ViewState private var scanned = false

    init(model: IslandModel) {
        self.model = model
        self.recents = model.recentApps
    }

    struct AppEntry: Identifiable, Equatable {
        let id: String
        let name: String
        let url: URL
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField(L("Поиск приложения"), text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.white.opacity(0.08)))
                .onSubmit { if let first = shown.first { open(first) } }

            if shown.isEmpty {
                HStack {
                    Spacer()
                    Text(query.isEmpty ? L("Пока пусто") : L("Ничего не нашлось"))
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.4))
                    Spacer()
                }
                .frame(maxHeight: .infinity)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 4) {
                        ForEach(shown) { entry in
                            Button { open(entry) } label: { row(entry) }
                                .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 20)
        .onAppear { if !scanned { scanned = true; scanInstalled() } }
        .onChange(of: query) { _ in if scanned && installed.isEmpty { scanInstalled() } }
    }

    private var shown: [AppEntry] {
        if query.isEmpty {
            return recents.entries.prefix(6).compactMap { entry in
                guard let url = recents.appURL(for: entry) else { return nil }
                return AppEntry(id: entry.bundleID, name: entry.name, url: url)
            }
        }
        let q = query.lowercased()
        return Array(installed.filter { $0.name.lowercased().contains(q) }.prefix(6))
    }

    private func row(_ entry: AppEntry) -> some View {
        HStack(spacing: 10) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: entry.url.path))
                .resizable()
                .frame(width: 26, height: 26)
            Text(entry.name)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white)
                .lineLimit(1)
            Spacer(minLength: 8)
            Image(systemName: "arrow.up.forward.app")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.4))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.white.opacity(0.05)))
        .contentShape(Rectangle())
    }

    private func open(_ entry: AppEntry) {
        NSWorkspace.shared.open(entry.url)
    }

    private func scanInstalled() {
        var found: [AppEntry] = []
        var seen = Set<String>()
        for base in ["/Applications", "/System/Applications"] {
            guard let items = try? FileManager.default.contentsOfDirectory(atPath: base) else { continue }
            for item in items where item.hasSuffix(".app") {
                let name = (item as NSString).deletingPathExtension
                guard seen.insert(name).inserted else { continue }
                let url = URL(fileURLWithPath: "\(base)/\(item)")
                found.append(AppEntry(id: "\(base)/\(item)", name: name, url: url))
            }
        }
        installed = found.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}
