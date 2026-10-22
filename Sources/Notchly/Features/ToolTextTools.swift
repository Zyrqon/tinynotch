import SwiftUI
import CryptoKit

// MARK: - 001 Чистка форматирования

struct StripFormatTool: View {
    @ViewState private var input = ""
    @ViewState private var output = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Button(L("Вставить")) { input = ToolClipboard.paste(); clean() }
                    .buttonStyle(.bordered).controlSize(.small)
                Button(L("Очистить")) { input = ""; output = "" }
                    .buttonStyle(.bordered).controlSize(.small)
                Spacer()
                Button(L("Копировать")) { ToolClipboard.copy(output) }
                    .buttonStyle(.bordered).controlSize(.small).disabled(output.isEmpty)
            }
            TextEditor(text: $input)
                .frame(minHeight: 80)
                .font(.system(.caption, design: .monospaced))
                .scrollContentBackground(.hidden)
                .background(.quinary, in: RoundedRectangle(cornerRadius: 8))
                .onChange(of: input) { _ in clean() }
            Text(output.isEmpty ? L("Результат появится здесь") : output)
                .font(.system(.caption, design: .monospaced))
                .frame(maxWidth: .infinity, minHeight: 50, alignment: .topLeading)
                .textSelection(.enabled)
        }
    }

    private func clean() {
        var text = input
        text = text.replacingOccurrences(of: "\u{00A0}", with: " ")
        text = text.replacingOccurrences(of: "\u{200B}", with: "")
        text = text.replacingOccurrences(of: "\u{2010}", with: "-")
        let lines = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        output = lines.joined(separator: "\n")
    }
}

// MARK: - 002 Счётчик символов

struct CharCountTool: View {
    @ViewState private var input = ""

    private var stats: (chars: Int, words: Int, lines: Int, noSpaces: Int) {
        let chars = input.count
        let words = input.split(whereSeparator: { $0.isWhitespace }).count
        let lines = input.isEmpty ? 0 : input.components(separatedBy: .newlines).count
        let noSpaces = input.filter { !$0.isWhitespace }.count
        return (chars, words, lines, noSpaces)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ToolInOut(placeholder: L("Вставь текст"), input: $input)
            TextEditor(text: $input).frame(minHeight: 90)
                .font(.system(.caption, design: .monospaced))
                .scrollContentBackground(.hidden)
                .background(.quinary, in: RoundedRectangle(cornerRadius: 8))
            let s = stats
            HStack(spacing: 12) {
                statCell(L("Символы"), s.chars)
                statCell(L("Без пробелов"), s.noSpaces)
                statCell(L("Слова"), s.words)
                statCell(L("Строки"), s.lines)
            }
        }
    }

    private func statCell(_ title: String, _ value: Int) -> some View {
        VStack(spacing: 2) {
            Text("\(value)").font(.headline)
            Text(title).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(.quinary, in: RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - 003 Регистр текста

struct CaseConvertTool: View {
    @ViewState private var input = ""
    @ViewState private var output = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ToolInOut(placeholder: L("Вставь текст"), input: $input)
            HStack(spacing: 6) {
                Button(L("КАПС")) { output = input.uppercased() }
                Button(L("строчные")) { output = input.lowercased() }
                Button(L("Каждое Слово")) { output = input.capitalized }
                Button(L("Как Предложение")) {
                    let lowered = input.lowercased()
                    var chars = Array(lowered)
                    if let first = chars.firstIndex(where: { !$0.isWhitespace }) { chars[first] = Character(chars[first].uppercased()) }
                    output = String(chars)
                }
            }
            .buttonStyle(.bordered).controlSize(.small)
            ToolCopyRow(text: output)
        }
    }
}

// MARK: - 004 Транслит RU→LAT

private let translitMap: [Character: String] = [
    "а": "a", "б": "b", "в": "v", "г": "g", "д": "d", "е": "e", "ё": "e", "ж": "zh",
    "з": "z", "и": "i", "й": "y", "к": "k", "л": "l", "м": "m", "н": "n", "о": "o",
    "п": "p", "р": "r", "с": "s", "т": "t", "у": "u", "ф": "f", "х": "kh", "ц": "ts",
    "ч": "ch", "ш": "sh", "щ": "sch", "ъ": "", "ы": "y", "ь": "", "э": "e", "ю": "yu", "я": "ya",
]

struct TranslitTool: View {
    @ViewState private var input = ""
    @ViewState private var output = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ToolInOut(placeholder: L("Привет, мир"), input: $input)
            Button(L("Транслитерировать")) { transliterate() }
                .buttonStyle(.bordered).controlSize(.small)
            ToolCopyRow(text: output)
        }
    }

    private func transliterate() {
        var result = ""
        for ch in input {
            if let mapped = translitMap[Character(ch.lowercased())] {
                let piece = mapped
                result += ch.isUppercase && !piece.isEmpty
                    ? piece.prefix(1).uppercased() + piece.dropFirst()
                    : piece
            } else {
                result.append(ch)
            }
        }
        output = result
    }
}

// MARK: - 005 Base64

struct Base64Tool: View {
    @ViewState private var input = ""
    @ViewState private var output = ""
    @ViewState private var error = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ToolInOut(placeholder: L("Текст или base64"), input: $input)
            HStack(spacing: 6) {
                Button(L("Закодировать")) { encode() }
                Button(L("Раскодировать")) { decode() }
            }.buttonStyle(.bordered).controlSize(.small)
            if !error.isEmpty {
                Text(error).font(.caption2).foregroundStyle(.red)
            }
            ToolCopyRow(text: output)
        }
    }

    private func encode() {
        error = ""
        output = Data(input.utf8).base64EncodedString()
    }

    private func decode() {
        error = ""
        guard let data = Data(base64Encoded: input.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            error = L("Это не похоже на base64")
            output = ""
            return
        }
        output = String(data: data, encoding: .utf8) ?? L("Не текст (бинарные данные)")
    }
}

// MARK: - 006 URL-кодирование

struct UrlEncodeTool: View {
    @ViewState private var input = ""
    @ViewState private var output = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ToolInOut(placeholder: L("https://example.com/поиск?q="), input: $input)
            HStack(spacing: 6) {
                Button(L("Закодировать")) {
                    output = input.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? input
                }
                Button(L("Раскодировать")) {
                    output = input.removingPercentEncoding ?? input
                }
            }.buttonStyle(.bordered).controlSize(.small)
            ToolCopyRow(text: output)
        }
    }
}

// MARK: - 007 JSON-форматтер

struct JsonFormatTool: View {
    @ViewState private var input = ""
    @ViewState private var output = ""
    @ViewState private var error = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Button(L("Вставить")) { input = ToolClipboard.paste(); format() }
                    .buttonStyle(.bordered).controlSize(.small)
                Button(L("Форматировать")) { format() }
                    .buttonStyle(.bordered).controlSize(.small)
                Spacer()
            }
            TextEditor(text: $input).frame(minHeight: 80)
                .font(.system(.caption, design: .monospaced))
                .scrollContentBackground(.hidden)
                .background(.quinary, in: RoundedRectangle(cornerRadius: 8))
                .onChange(of: input) { _ in format() }
            if !error.isEmpty {
                Text(error).font(.caption2).foregroundStyle(.red)
            }
            Text(output.isEmpty ? "—" : output)
                .font(.system(.caption, design: .monospaced))
                .frame(maxWidth: .infinity, minHeight: 60, alignment: .topLeading)
                .textSelection(.enabled)
        }
    }

    private func format() {
        output = ""
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { error = ""; return }
        do {
            let data = try JSONSerialization.jsonObject(with: Data(trimmed.utf8))
            let pretty = try JSONSerialization.data(withJSONObject: data, options: [.prettyPrinted, .sortedKeys])
            error = ""
            output = String(data: pretty, encoding: .utf8) ?? ""
        } catch {
            self.error = L("Не JSON") + ": " + error.localizedDescription
        }
    }
}

// MARK: - 008 SHA-256

struct Sha256Tool: View {
    @ViewState private var input = ""

    private var hash: String {
        SHA256.hash(data: Data(input.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ToolInOut(placeholder: L("Любой текст"), input: $input)
            ToolCopyRow(text: hash)
        }
    }
}

// MARK: - 009 UUID

struct UuidTool: View {
    @ViewState private var value = UUID().uuidString
    @ViewState private var count = 1

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Stepper(value: $count, in: 1...20) {
                Text(L("Сколько: ") + "\(count)")
            }
            HStack(spacing: 6) {
                Button(L("Сгенерировать")) { value = (0..<count).map { _ in UUID().uuidString }.joined(separator: "\n") }
                    .buttonStyle(.bordered).controlSize(.small)
            }
            ToolCopyRow(text: value)
        }
    }
}

// MARK: - 010 Генератор паролей

struct PassGenTool: View {
    @ViewState private var length: Double = 16
    @ViewState private var useUpper = true
    @ViewState private var useDigits = true
    @ViewState private var useSymbols = true
    @ViewState private var password = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(L("Длина"))
                Slider(value: $length, in: 8...64, step: 1)
                Text("\(Int(length))").font(.system(.caption, design: .monospaced))
            }
            Toggle(L("Заглавные A-Z"), isOn: $useUpper).toggleStyle(.switch).controlSize(.small)
            Toggle(L("Цифры 0-9"), isOn: $useDigits).toggleStyle(.switch).controlSize(.small)
            Toggle(L("Символы !@#$"), isOn: $useSymbols).toggleStyle(.switch).controlSize(.small)
            Button(L("Сгенерировать")) { generate() }.buttonStyle(.bordered).controlSize(.small)
            ToolCopyRow(text: password)
        }
        .onAppear { generate() }
    }

    private func generate() {
        var pool = "abcdefghijklmnopqrstuvwxyz"
        if useUpper { pool += "ABCDEFGHIJKLMNOPQRSTUVWXYZ" }
        if useDigits { pool += "0123456789" }
        if useSymbols { pool += "!@#$%^&*()-_=+?" }
        guard !pool.isEmpty else { password = ""; return }
        password = String((0..<Int(length)).map { _ in pool.randomElement() ?? "a" })
    }
}

// MARK: - 011 Unix-время

struct UnixTimeTool: View {
    @ViewState private var epochInput = ""
    @ViewState private var dateOutput = ""
    @ViewState private var pickedDate = Date()
    @ViewState private var epochOutput = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ToolBox(title: L("Unix → дата")) {
                HStack(spacing: 6) {
                    Button(L("Сейчас")) {
                        let now = Int(Date().timeIntervalSince1970)
                        epochInput = String(now)
                        convert()
                    }.buttonStyle(.bordered).controlSize(.small)
                    TextField("1778900000", text: $epochInput).textFieldStyle(.roundedBorder)
                        .onSubmit { convert() }
                }
                ToolCopyRow(text: dateOutput)
            }
            ToolBox(title: L("Дата → Unix")) {
                DatePicker(L("Дата"), selection: $pickedDate).labelsHidden()
                ToolCopyRow(text: String(Int(pickedDate.timeIntervalSince1970)))
            }
        }
    }

    private func convert() {
        guard let seconds = TimeInterval(epochInput.trimmingCharacters(in: .whitespaces)) else {
            dateOutput = L("Введите число"); return
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "dd.MM.yyyy HH:mm:ss"
        formatter.timeZone = TimeZone.current
        dateOutput = formatter.string(from: Date(timeIntervalSince1970: seconds))
    }
}

// MARK: - 012 Regex-тестер

struct RegexTestTool: View {
    @ViewState private var pattern = ""
    @ViewState private var text = ""
    @ViewState private var result = ""
    @ViewState private var error = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField(L("Шаблон, например \\d+"), text: $pattern).textFieldStyle(.roundedBorder)
            TextEditor(text: $text).frame(minHeight: 70)
                .font(.system(.caption, design: .monospaced))
                .scrollContentBackground(.hidden)
                .background(.quinary, in: RoundedRectangle(cornerRadius: 8))
            Button(L("Найти")) { run() }.buttonStyle(.bordered).controlSize(.small)
            if !error.isEmpty { Text(error).font(.caption2).foregroundStyle(.red) }
            Text(result.isEmpty ? "—" : result)
                .font(.system(.caption, design: .monospaced))
                .frame(maxWidth: .infinity, minHeight: 40, alignment: .topLeading)
                .textSelection(.enabled)
        }
    }

    private func run() {
        error = ""
        result = ""
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            error = L("Шаблон не разбирается"); return
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        let matches = regex.matches(in: text, range: range)
        result = matches.compactMap { match in
            guard let r = Range(match.range, in: text) else { return nil }
            return "\(text[r]) [\(match.range.location)…\(match.range.location + match.range.length)]"
        }.joined(separator: "\n")
        if result.isEmpty { result = L("Совпадений нет") }
    }
}

// MARK: - 013 Diff текстов

private enum DiffLine { case same(String), removed(String), added(String) }

struct TextDiffTool: View {
    @ViewState private var left = ""
    @ViewState private var right = ""
    @ViewState private var lines: [DiffLine] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                TextEditor(text: $left).frame(minHeight: 80)
                    .font(.system(.caption, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .background(.quinary, in: RoundedRectangle(cornerRadius: 8))
                TextEditor(text: $right).frame(minHeight: 80)
                    .font(.system(.caption, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .background(.quinary, in: RoundedRectangle(cornerRadius: 8))
            }
            Button(L("Сравнить")) { lines = Self.diff(left: leftLines, right: rightLines) }
                .buttonStyle(.bordered).controlSize(.small)
            if lines.isEmpty {
                Text(L("Строки с − были в левом, с + в правом")).font(.caption2).foregroundStyle(.secondary)
            }
            ForEach(Array(lines.enumerated()), id: \.offset) { pair in
                Text(rowText(pair.element))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(rowColor(pair.element))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var leftLines: [String] {
        left.components(separatedBy: .newlines).filter { !$0.isEmpty }
    }
    private var rightLines: [String] {
        right.components(separatedBy: .newlines).filter { !$0.isEmpty }
    }

    private func rowText(_ line: DiffLine) -> String {
        switch line {
        case .same(let s): return "  " + s
        case .removed(let s): return "- " + s
        case .added(let s): return "+ " + s
        }
    }

    private func rowColor(_ line: DiffLine) -> Color {
        switch line {
        case .same: return .secondary
        case .removed: return .red
        case .added: return .green
        }
    }

    private static func diff(left a: [String], right b: [String]) -> [DiffLine] {
        let n = a.count, m = b.count
        var table = Array(repeating: Array(repeating: 0, count: m + 1), count: n + 1)
        for i in stride(from: n - 1, through: 0, by: -1) {
            for j in stride(from: m - 1, through: 0, by: -1) {
                table[i][j] = a[i] == b[j] ? table[i + 1][j + 1] + 1 : max(table[i + 1][j], table[i][j + 1])
            }
        }
        var result: [DiffLine] = []
        var i = 0, j = 0
        while i < n && j < m {
            if a[i] == b[j] { result.append(.same(a[i])); i += 1; j += 1 }
            else if table[i + 1][j] >= table[i][j + 1] { result.append(.removed(a[i])); i += 1 }
            else { result.append(.added(b[j])); j += 1 }
        }
        while i < n { result.append(.removed(a[i])); i += 1 }
        while j < m { result.append(.added(b[j])); j += 1 }
        return result
    }
}

// MARK: - 014 Lorem ipsum

struct LoremTool: View {
    @ViewState private var words: Double = 40
    @ViewState private var output = ""

    private let pool = ["lorem", "ipsum", "dolor", "sit", "amet", "consectetur", "adipiscing", "elit",
                        "sed", "do", "eiusmod", "tempor", "incididunt", "ut", "labore", "et", "dolore",
                        "magna", "aliqua", "enim", "ad", "minim", "veniam", "quis", "nostrud",
                        "exercitation", "ullamco", "laboris", "nisi", "aliquip", "ex", "ea", "commodo"]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(L("Слов"))
                Slider(value: $words, in: 5...200, step: 5)
                Text("\(Int(words))").font(.system(.caption, design: .monospaced))
            }
            Button(L("Сгенерировать")) { generate() }.buttonStyle(.bordered).controlSize(.small)
            ToolCopyRow(text: output)
        }
        .onAppear { generate() }
    }

    private func generate() {
        var result: [String] = []
        for _ in 0..<Int(words) { result.append(pool.randomElement() ?? "lorem") }
        if let first = result.indices.first {
            result[first] = result[first].prefix(1).uppercased() + result[first].dropFirst()
        }
        output = result.joined(separator: " ") + "."
    }
}

// MARK: - 015 Морзе

private let morseTable: [Character: String] = [
    "а": ".-", "б": "-...", "в": ".--", "г": "--.", "д": "-..", "е": ".", "ё": ".", "ж": "...-",
    "з": "--..", "и": "..", "й": ".---", "к": "-.-", "л": ".-..", "м": "--", "н": "-.", "о": "---",
    "п": ".--.", "р": ".-.", "с": "...", "т": "-", "у": "..-", "ф": "..-.", "х": "....", "ц": "-.-.",
    "ч": "---.", "ш": "----", "щ": "--.-", "ъ": "--.--", "ы": "-.--", "ь": "-..-", "э": "..-..",
    "ю": "..--", "я": ".-.-",
    "a": ".-", "b": "-...", "c": "-.-.", "d": "-..", "e": ".", "f": "..-.", "g": "--.", "h": "....",
    "i": "..", "j": ".---", "k": "-.-", "l": ".-..", "m": "--", "n": "-.", "o": "---", "p": ".--.",
    "q": "--.-", "r": ".-.", "s": "...", "t": "-", "u": "..-", "v": "...-", "w": ".--", "x": "-..-",
    "y": "-.--", "z": "--..", "0": "-----", "1": ".----", "2": "..---", "3": "...--", "4": "....-",
    "5": ".....", "6": "-....", "7": "--...", "8": "---..", "9": "----.",
]

private let morseReverse: [String: String] = {
    var map: [String: String] = [:]
    for (key, value) in morseTable where map[value] == nil { map[value] = String(key) }
    return map
}()

struct MorseTool: View {
    @ViewState private var input = ""
    @ViewState private var output = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ToolInOut(placeholder: L("Текст или код Морзе"), input: $input)
            Button(L("Перевести")) { convert() }.buttonStyle(.bordered).controlSize(.small)
            ToolCopyRow(text: output)
        }
    }

    private func convert() {
        let source = input.lowercased()
        if source.contains(".") || source.contains("-") {
            let words = source.components(separatedBy: " / ")
            let decoded = words.map { word in
                word.split(separator: " ").compactMap { morseReverse[String($0)] }.joined()
            }
            output = decoded.joined(separator: " ")
        } else {
            let encoded = source.map { ch -> String in
                if ch == " " { return "/" }
                if let code = morseTable[ch] { return code }
                return String(ch)
            }
            output = encoded.joined(separator: " ")
        }
    }
}

// MARK: - 016 Римские цифры

struct RomanTool: View {
    @ViewState private var input = ""
    @ViewState private var output = ""

    private let romanValues: [(String, Int)] = [
        ("M", 1000), ("CM", 900), ("D", 500), ("CD", 400), ("C", 100), ("XC", 90),
        ("L", 50), ("XL", 40), ("X", 10), ("IX", 9), ("V", 5), ("IV", 4), ("I", 1),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ToolInOut(placeholder: L("2026 или MMXXVI"), input: $input)
            Button(L("Перевести")) { convert() }.buttonStyle(.bordered).controlSize(.small)
            ToolCopyRow(text: output)
        }
    }

    private func convert() {
        let value = input.trimmingCharacters(in: .whitespaces).lowercased()
        if let number = Int(value) {
            output = Self.toRoman(number, values: romanValues)
        } else {
            var total = 0
            let upper = value.uppercased()
            var index = upper.startIndex
            for (symbol, amount) in romanValues {
                while upper[index...].hasPrefix(symbol) {
                    total += amount
                    index = upper.index(index, offsetBy: symbol.count)
                }
            }
            output = total > 0 ? String(total) : L("Не похоже на римские цифры")
        }
    }

    private static func toRoman(_ number: Int, values: [(String, Int)]) -> String {
        guard number > 0, number < 4000 else { return "?" }
        var rest = number
        var result = ""
        for (symbol, amount) in values {
            while rest >= amount { result += symbol; rest -= amount }
        }
        return result
    }
}
