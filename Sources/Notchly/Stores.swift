import AppKit
import SwiftUI

/// Переезд со старого имени проекта (Dynamic Island → Notchly): данные и настройки переносятся один раз.
enum LegacyMigration {
    private static let oldBundleID = "dev.aleksandrsenko.DynamicIsland"
    private static let doneKey = "migration.fromDynamicIsland"

    static func run() {
        let fm = FileManager.default
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let old = base.appendingPathComponent("DynamicIsland", isDirectory: true)
        let new = base.appendingPathComponent("Notchly", isDirectory: true)
        // Файл за файлом: переносим только то, чего в новой папке ещё нет.
        if let files = try? fm.contentsOfDirectory(atPath: old.path) {
            try? fm.createDirectory(at: new, withIntermediateDirectories: true)
            for file in files where !fm.fileExists(atPath: new.appendingPathComponent(file).path) {
                try? fm.copyItem(at: old.appendingPathComponent(file), to: new.appendingPathComponent(file))
            }
        }
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: doneKey) else { return }
        if let legacy = defaults.persistentDomain(forName: oldBundleID) {
            for (key, value) in legacy where defaults.object(forKey: key) == nil {
                defaults.set(value, forKey: key)
            }
        }
        defaults.set(true, forKey: doneKey)
    }
}

private let supportDirectory: URL = {
    let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    let dir = base.appendingPathComponent("Notchly", isDirectory: true)
    // Папка и файлы с задачами и заметками доступны только владельцу (700 / 600).
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true,
                                             attributes: [.posixPermissions: 0o700])
    try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: dir.path)
    return dir
}()

private func load<T: Decodable>(_ type: T.Type, from file: String) -> T? {
    guard let data = try? Data(contentsOf: supportDirectory.appendingPathComponent(file)) else { return nil }
    return try? JSONDecoder().decode(type, from: data)
}

private func save<T: Encodable>(_ value: T, to file: String) {
    guard let data = try? JSONEncoder().encode(value) else { return }
    let url = supportDirectory.appendingPathComponent(file)
    try? data.write(to: url, options: .atomic)
    try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
}

// MARK: - Полка временных файлов

struct ShelfItem: Identifiable, Codable, Equatable {
    var id = UUID()
    var url: URL
    var addedAt = Date()

    var name: String { url.lastPathComponent }
    var exists: Bool { FileManager.default.fileExists(atPath: url.path) }
}

/// Полка хранит ссылки на файлы: перетащил сюда, а позже вытащил туда, куда нужно.
final class ShelfStore: ObservableObject {
    @Published private(set) var items: [ShelfItem] = []

    private let persistent: Bool

    /// persistent = false — для снапшотов: ничего не читаем и не пишем на диск.
    init(persistent: Bool = true) {
        self.persistent = persistent
        items = persistent ? (load([ShelfItem].self, from: "shelf.json") ?? []).filter(\.exists) : []
    }

    func add(_ urls: [URL]) {
        let known = Set(items.map(\.url))
        let fresh = urls.filter { !known.contains($0) }.map { ShelfItem(url: $0) }
        guard !fresh.isEmpty else { return }
        withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
            items.insert(contentsOf: fresh, at: 0)
        }
        persist()
    }

    func remove(_ item: ShelfItem) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            items.removeAll { $0.id == item.id }
        }
        persist()
    }

    func removeAll() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { items.removeAll() }
        persist()
    }

    private func persist() {
        guard persistent else { return }
        save(items, to: "shelf.json")
    }
}

// MARK: - Заметки

struct Note: Identifiable, Codable, Equatable {
    var id = UUID()
    /// Простой текст — для заголовка и поиска.
    var text: String
    var updatedAt = Date()
    /// Текст с форматированием (жирный, курсив, размер…).
    var rtf: Data?
    /// Имя, которое задали вручную; иначе заголовок — первая строка.
    var customTitle: String?

    var title: String { Note.title(text: text, custom: customTitle) }

    /// Первая непустая строка, не длиннее `titleLimit` символов (в списке она всё равно обрезается).
    /// Смотрим только начало текста: вызывается при каждой напечатанной букве.
    static func title(text: String, custom: String?) -> String {
        if let custom, !custom.isEmpty { return custom }
        let isBreak: (Character) -> Bool = { $0 == "\n" || $0 == "\r\n" }
        let first = text.drop(while: isBreak).prefix(titleLimit).prefix { !isBreak($0) }
        return first.trimmingCharacters(in: .whitespaces).isEmpty ? L("Новая заметка") : String(first)
    }

    static let titleLimit = 120
}

final class NotesStore: ObservableObject {
    @Published private(set) var notes: [Note] = []
    @Published var selectedID: UUID? { willSet { flushPending() } }

    private var saveWork: DispatchWorkItem?
    /// Текст, который печатают прямо сейчас. В `notes` он попадает, только когда меняется то, что видно в списке
    /// (заголовок, пустая ли заметка), и при сохранении. Иначе каждая буква пересобирала бы весь экран заметок
    /// и заново сериализовала всю заметку в RTF.
    private var pending: (id: UUID, value: NSAttributedString)?

    private let persistent: Bool

    /// persistent = false — для снапшотов: ничего не читаем и не пишем на диск.
    init(persistent: Bool = true) {
        self.persistent = persistent
        notes = persistent ? (load([Note].self, from: "notes.json") ?? []) : []
        if notes.isEmpty { notes = [Note(text: "")] }
        selectedID = notes.first?.id
    }

    var selected: Note? { notes.first { $0.id == selectedID } }

    func create() {
        flushPending()
        let note = Note(text: "")
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            notes.insert(note, at: 0)
            selectedID = note.id
        }
        persist()
    }

    func delete(_ id: UUID) {
        if pending?.id == id { pending = nil }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            notes.removeAll { $0.id == id }
            if notes.isEmpty { notes = [Note(text: "")] }
            if selectedID == id { selectedID = notes.first?.id }
        }
        persist()
    }

    func attributed(for id: UUID) -> NSAttributedString {
        if let pending, pending.id == id { return pending.value }
        guard let note = notes.first(where: { $0.id == id }) else { return NSAttributedString() }
        if let rtf = note.rtf, let value = NSAttributedString(rtf: rtf, documentAttributes: nil) { return value }
        return NSAttributedString(string: note.text, attributes: RichTextEditor.defaultAttributes)
    }

    func updateRich(_ id: UUID, _ value: NSAttributedString) {
        guard let index = notes.firstIndex(where: { $0.id == id }) else { return }
        if let pending, pending.id != id { flushPending() }
        pending = (id, value)
        let note = notes[index]
        let text = value.string
        if text.isEmpty != note.text.isEmpty
            || Note.title(text: text, custom: note.customTitle) != note.title {
            flushPending()
        }
        // Пишем на диск с небольшой задержкой, чтобы не делать это на каждую букву.
        saveWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.persist() }
        saveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    /// Переносит напечатанное в `notes`: простой текст, RTF и время изменения.
    private func flushPending() {
        guard let (id, value) = pending else { return }
        pending = nil
        guard let index = notes.firstIndex(where: { $0.id == id }) else { return }
        notes[index].rtf = value.rtf(from: NSRange(location: 0, length: value.length), documentAttributes: [:])
        notes[index].text = value.string
        notes[index].updatedAt = Date()
    }

    func rename(_ id: UUID, to title: String) {
        guard let index = notes.firstIndex(where: { $0.id == id }) else { return }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        notes[index].customTitle = trimmed.isEmpty ? nil : trimmed
        persist()
    }

    func persist() {
        flushPending()
        guard persistent else { return }
        save(notes, to: "notes.json")
    }
}

// MARK: - Задачи

struct TaskItem: Identifiable, Codable, Equatable {
    var id = UUID()
    var text: String
    var done = false
    /// Время в формате «ЧЧ:ММ», если задача привязана ко времени.
    var time: String?
    var createdAt = Date()
    /// Описание под задачей: заметки, ссылка на урок и т. п.
    var notes: String?
    /// День задачи (начало дня). У старых задач его нет — тогда считается день создания.
    var day: Date?

    /// Ссылки из описания — открываются кнопками и из напоминания.
    var links: [URL] { TaskItem.links(in: notes ?? "") }

    static func links(in text: String) -> [URL] {
        guard !text.isEmpty, let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        else { return [] }
        return detector.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap(\.url)
            .filter(isSafeLink)
    }

    /// Открываем только веб-ссылки: file://, x-apple… и прочие схемы из текста задачи не запускаем.
    static func isSafeLink(_ url: URL) -> Bool {
        ["http", "https"].contains(url.scheme?.lowercased() ?? "")
    }
}

/// Компактный список дел. Сохраняется сразу после каждого изменения.
final class TasksStore: ObservableObject {
    @Published private(set) var items: [TaskItem] = []
    /// Мини-планер: выбранный день — 0 (сегодня) … 6. Дальше недели задачи не планируются.
    @Published var selectedDay = 0
    static let days = 7
    private let persistent: Bool

    init(persistent: Bool = true) {
        self.persistent = persistent
        if persistent {
            items = load([TaskItem].self, from: "tasks.json") ?? []
            // Выполненные задачи старше недели больше нигде не показываются — убираем их.
            let weekAgo = Self.date(forOffset: -7)
            let kept = items.filter { !$0.done || Self.day(of: $0) >= weekAgo }
            if kept.count != items.count { items = kept; persist() }
        }
    }

    static func date(forOffset offset: Int) -> Date {
        let cal = Calendar.current
        return cal.date(byAdding: .day, value: offset, to: cal.startOfDay(for: Date())) ?? Date()
    }

    static func day(of task: TaskItem) -> Date {
        Calendar.current.startOfDay(for: task.day ?? task.createdAt)
    }

    /// Задачи дня. В «сегодня» попадают и невыполненные задачи прошлых дней — они переносятся сами.
    func tasks(forOffset offset: Int) -> [TaskItem] {
        let target = Self.date(forOffset: offset)
        return items.filter { task in
            let day = Self.day(of: task)
            return day == target || (offset == 0 && day < target && !task.done)
        }
        .sorted { a, b in
            // Невыполненные сверху (по времени), выполненные внизу.
            if a.done != b.done { return !a.done }
            switch (a.time, b.time) {
            case let (x?, y?) where x != y: return x < y
            case (_?, nil): return true
            case (nil, _?): return false
            default: return a.createdAt < b.createdAt
            }
        }
    }

    func openCount(forOffset offset: Int) -> Int {
        tasks(forOffset: offset).filter { !$0.done }.count
    }

    /// Новая задача попадает в выбранный день планера.
    func add(_ text: String, time: String? = nil, dayOffset: Int? = nil) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var item = TaskItem(text: trimmed, time: time)
        item.day = Self.date(forOffset: dayOffset ?? selectedDay)
        withAnimation(.spring(response: 0.4, dampingFraction: 0.88)) { items.append(item) }
        persist()
    }

    func toggle(_ id: UUID) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        withAnimation(.spring(response: 0.4, dampingFraction: 0.88)) { items[i].done.toggle() }
        persist()
    }

    func update(_ id: UUID, text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        if trimmed.isEmpty { return remove(id) }
        // Время можно поправить прямо в тексте: «Спортзал 18:30».
        if let match = trimmed.range(of: #"\s(\d{1,2}[:.]\d{2})$"#, options: .regularExpression),
           let time = GeminiAssistant.normalizedTime(String(trimmed[match]).trimmingCharacters(in: .whitespaces)) {
            items[i].text = String(trimmed[..<match.lowerBound])
            items[i].time = time
        } else {
            items[i].text = trimmed
        }
        persist()
    }

    func updateNotes(_ id: UUID, _ notes: String) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        let value = notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : notes
        guard items[i].notes != value else { return }
        items[i].notes = value
        persist()
    }

    func remove(_ id: UUID) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) { items.removeAll { $0.id == id } }
        persist()
    }

    /// Убирает выполненные задачи выбранного дня.
    func clearDone() {
        let ids = Set(tasks(forOffset: selectedDay).filter(\.done).map(\.id))
        withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) { items.removeAll { ids.contains($0.id) } }
        persist()
    }

    /// Для снапшотов.
    func debugSet(_ items: [TaskItem]) { self.items = items }

    private func persist() {
        guard persistent else { return }
        save(items, to: "tasks.json")
    }
}
