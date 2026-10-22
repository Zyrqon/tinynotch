import SwiftUI
import EventKit

// MARK: - 070 Погода

struct WeatherNowTool: View {
    @ViewState private var text = L("Проверяю…")

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(text).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
            Button(L("Обновить")) { fetch() }.buttonStyle(.bordered).controlSize(.small)
        }
        .onAppear { fetch() }
    }

    private func fetch() {
        text = L("Проверяю…")
        guard let url = URL(string: "https://wttr.in/?format=3&lang=ru") else { return }
        URLSession.shared.dataTask(with: url) { data, _, _ in
            let body = data.flatMap { String(data: $0, encoding: .utf8) } ?? L("Не получилось")
            DispatchQueue.main.async { text = body.trimmingCharacters(in: .whitespacesAndNewlines) }
        }.resume()
    }
}

// MARK: - 071 Курсы в строке

private struct DailyRates: Codable {
    struct Valute: Codable { let Value: Double }
    let Valute: [String: Valute]
}

struct RatesLiveTool: View {
    @ViewState private var line = L("Загружаю курсы ЦБ…")
    @ViewState private var failed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(line).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
            Button(L("Обновить")) { fetch() }.buttonStyle(.bordered).controlSize(.small)
            if failed {
                Text(L("Нет сети — покажу кэш из тула «Курс валют»"))
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
        .onAppear { fetch() }
    }

    private func fetch() {
        failed = false
        guard let url = URL(string: "https://www.cbr-xml-daily.ru/daily_json.js") else { return }
        URLSession.shared.dataTask(with: url) { data, _, _ in
            guard let data, let rates = try? JSONDecoder().decode(DailyRates.self, from: data) else {
                DispatchQueue.main.async { failed = true; line = L("Курсы не загрузились") }
                return
            }
            let usd = rates.Valute["USD"]?.Value ?? 0
            let eur = rates.Valute["EUR"]?.Value ?? 0
            let cny = rates.Valute["CNY"]?.Value ?? 0
            DispatchQueue.main.async {
                line = String(format: "$ %.2f ₽ · € %.2f ₽ · ¥ %.2f ₽", usd, eur, cny)
            }
        }.resume()
    }
}

// MARK: - 072/079 Заметки-хранилище

enum ToolStorage {
    static func file(_ name: String) -> URL {
        let folder = URL(fileURLWithPath: NSHomeDirectory() + "/Library/Application Support/Notchly Tools")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent(name)
    }
    static func load(_ name: String) -> String {
        (try? String(contentsOf: file(name), encoding: .utf8)) ?? ""
    }
    static func save(_ name: String, _ value: String) {
        try? value.write(to: file(name), atomically: true, encoding: .utf8)
    }
}

struct QuickStickyTool: View {
    @ViewState private var text = ToolStorage.load("sticky.txt")

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextEditor(text: $text).frame(minHeight: 120)
                .font(.system(.caption, design: .monospaced))
                .scrollContentBackground(.hidden)
                .background(.quinary, in: RoundedRectangle(cornerRadius: 8))
                .onChange(of: text) { ToolStorage.save("sticky.txt", $0) }
            Text(L("Сохраняется само")).font(.caption2).foregroundStyle(.secondary)
        }
    }
}

struct ScratchpadTool: View {
    @ViewState private var text = ToolStorage.load("scratchpad.txt")

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextEditor(text: $text).frame(minHeight: 160)
                .font(.system(.caption, design: .monospaced))
                .scrollContentBackground(.hidden)
                .background(.quinary, in: RoundedRectangle(cornerRadius: 8))
                .onChange(of: text) { ToolStorage.save("scratchpad.txt", $0) }
            HStack {
                Text(L("Черновик с автосохранением")).font(.caption2).foregroundStyle(.secondary)
                Spacer()
                Button(L("Копировать всё")) { ToolClipboard.copy(text) }.buttonStyle(.bordered).controlSize(.mini)
            }
        }
    }
}

// MARK: - 073 Чеклист покупок

private struct ShoppingItem: Codable, Identifiable {
    var id = UUID()
    var title: String
    var done: Bool = false
}

struct ShoppingListTool: View {
    @ViewState private var items: [ShoppingItem] = {
        if let data = FileManager.default.contents(atPath: ToolStorage.file("shopping.json").path),
           let saved = try? JSONDecoder().decode([ShoppingItem].self, from: data) {
            return saved
        }
        return []
    }()
    @ViewState private var draft = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                TextField(L("Добавить"), text: $draft).textFieldStyle(.roundedBorder)
                    .onSubmit { add() }
                Button(L("+")) { add() }.buttonStyle(.bordered).controlSize(.small)
            }
            ForEach(items) { item in
                HStack {
                    Button {
                        if let index = items.firstIndex(where: { $0.id == item.id }) {
                            items[index].done.toggle()
                            persist()
                        }
                    } label: {
                        Image(systemName: item.done ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(item.done ? .green : .secondary)
                    }.buttonStyle(.plain)
                    Text(item.title)
                        .font(.caption)
                        .strikethrough(item.done)
                        .foregroundStyle(item.done ? .secondary : .primary)
                    Spacer()
                    Button {
                        items.removeAll { $0.id == item.id }
                        persist()
                    } label: {
                        Image(systemName: "xmark").font(.caption2).foregroundStyle(.secondary)
                    }.buttonStyle(.plain)
                }
            }
            if !items.isEmpty {
                Button(L("Убрать купленное")) {
                    items.removeAll { $0.done }
                    persist()
                }.buttonStyle(.bordered).controlSize(.mini)
            }
        }
    }

    private func add() {
        let title = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        items.append(ShoppingItem(title: title))
        draft = ""
        persist()
    }

    private func persist() {
        let data = (try? JSONEncoder().encode(items)) ?? Data()
        try? data.write(to: ToolStorage.file("shopping.json"))
    }
}

// MARK: - 074 RSS

struct RssFeedTool: View {
    @ViewState private var feedURL = "https://habr.com/ru/rss/news/?fl=ru"
    @ViewState private var titles: [String] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ToolInOut(placeholder: L("Ссылка на RSS"), input: $feedURL)
            Button(L("Загрузить")) { fetch() }.buttonStyle(.bordered).controlSize(.small)
            ForEach(Array(titles.enumerated()), id: \.offset) { pair in
                Text("\(pair.offset + 1). \(pair.element)")
                    .font(.caption).lineLimit(1).truncationMode(.tail)
            }
        }
        .onAppear { fetch() }
    }

    private func fetch() {
        let trimmed = feedURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), trimmed.contains("http") else { return }
        URLSession.shared.dataTask(with: url) { data, _, _ in
            let body = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
            let found = body.components(separatedBy: "<title>")
                .dropFirst()
                .compactMap { piece -> String? in
                    guard let end = piece.range(of: "</title>") else { return nil }
                    var title = String(piece[..<end.lowerBound])
                    title = title
                        .replacingOccurrences(of: "<![CDATA[", with: "")
                        .replacingOccurrences(of: "]]>", with: "")
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    return title.isEmpty ? nil : title
                }
            DispatchQueue.main.async { titles = Array(found.prefix(8)) }
        }.resume()
    }
}

// MARK: - 075 Hacker News

struct HnFeedTool: View {
    @ViewState private var rows: [String] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(L("Обновить")) { fetch() }.buttonStyle(.bordered).controlSize(.small)
            ForEach(Array(rows.enumerated()), id: \.offset) { pair in
                Text("\(pair.offset + 1). \(pair.element)")
                    .font(.caption).lineLimit(2)
            }
        }
        .onAppear { fetch() }
    }

    private func fetch() {
        guard let url = URL(string: "https://hacker-news.firebaseio.com/v0/topstories.json") else { return }
        URLSession.shared.dataTask(with: url) { data, _, _ in
            guard let data, let ids = try? JSONDecoder().decode([Int].self, from: data) else { return }
            let top = Array(ids.prefix(8))
            let group = DispatchGroup()
            var titles: [String] = []
            let lock = NSLock()
            for id in top {
                group.enter()
                guard let itemURL = URL(string: "https://hacker-news.firebaseio.com/v0/item/\(id).json") else {
                    group.leave(); continue
                }
                URLSession.shared.dataTask(with: itemURL) { itemData, _, _ in
                    defer { group.leave() }
                    guard let itemData,
                          let payload = try? JSONSerialization.jsonObject(with: itemData) as? [String: Any],
                          let title = payload["title"] as? String else { return }
                    lock.lock()
                    titles.append(title)
                    lock.unlock()
                }.resume()
            }
            group.notify(queue: .main) { rows = titles }
        }.resume()
    }
}

// MARK: - 076 Дни рождения

private struct BirthdayEntry: Codable, Identifiable {
    var id = UUID()
    var name: String
    var date: String // MM-DD
}

struct BirthdaysNearTool: View {
    @ViewState private var entries: [BirthdayEntry] = {
        if let data = FileManager.default.contents(atPath: ToolStorage.file("birthdays.json").path),
           let saved = try? JSONDecoder().decode([BirthdayEntry].self, from: data) {
            return saved
        }
        return []
    }()
    @ViewState private var name = ""
    @ViewState private var date = ""

    private var sorted: [BirthdayEntry] {
        entries.sorted { $0.date < $1.date }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                TextField(L("Имя"), text: $name).textFieldStyle(.roundedBorder)
                TextField(L("дд.мм"), text: $date).textFieldStyle(.roundedBorder).frame(width: 70)
                Button(L("+")) { add() }.buttonStyle(.bordered).controlSize(.small)
            }
            ForEach(sorted) { entry in
                HStack {
                    Text(entry.name).font(.caption)
                    Spacer()
                    Text(entry.date).font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
                    Button {
                        entries.removeAll { $0.id == entry.id }
                        persist()
                    } label: {
                        Image(systemName: "xmark").font(.caption2).foregroundStyle(.secondary)
                    }.buttonStyle(.plain)
                }
            }
        }
    }

    private func add() {
        let cleaned = date.replacingOccurrences(of: ".", with: "-")
        guard !name.isEmpty, cleaned.count >= 4 else { return }
        let parts = cleaned.split(separator: "-")
        let normalized = parts.count == 2 ? "\(parts[1])-\(parts[0])" : cleaned
        entries.append(BirthdayEntry(name: name, date: normalized))
        name = ""
        date = ""
        persist()
    }

    private func persist() {
        let data = (try? JSONEncoder().encode(entries)) ?? Data()
        try? data.write(to: ToolStorage.file("birthdays.json"))
    }
}

// MARK: - 077 В Telegram себе

struct TgSelfTool: View {
    @ViewState private var text = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextEditor(text: $text).frame(minHeight: 70)
                .font(.system(.caption, design: .monospaced))
                .scrollContentBackground(.hidden)
                .background(.quinary, in: RoundedRectangle(cornerRadius: 8))
            HStack(spacing: 6) {
                Button(L("Отправить в Избранное")) {
                    let encoded = text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
                    guard let url = URL(string: "https://t.me/share/url?url=&text=\(encoded)") else { return }
                    NSWorkspace.shared.open(url)
                }.buttonStyle(.bordered).controlSize(.small)
                Button(L("Копировать")) { ToolClipboard.copy(text) }.buttonStyle(.bordered).controlSize(.small)
            }
            Text(L("Откроется Telegram — выбери «Избранное» и отправь"))
                .font(.caption2).foregroundStyle(.secondary)
        }
    }
}

// MARK: - 078 Расписание сегодня

struct SysScheduleTool: View {
    @ViewState private var rows: [String] = []
    @ViewState private var granted = false
    @ViewState private var store = EKEventStore()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(granted ? L("Обновить") : L("Дать доступ к календарю")) { request() }
                .buttonStyle(.bordered).controlSize(.small)
            ForEach(rows, id: \.self) { row in
                Text(row).font(.caption).lineLimit(1)
            }
            if granted && rows.isEmpty {
                Text(L("На сегодня событий нет")).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func request() {
        store.requestFullAccessToEvents { allowed, _ in
            granted = allowed
            if allowed { fetch() }
        }
    }

    private func fetch() {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: Date())
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        let events = store.events(matching: predicate).sorted { $0.startDate < $1.startDate }
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        rows = events.map { event in
            "\(formatter.string(from: event.startDate)) \(event.title ?? "—")"
        }
    }
}
