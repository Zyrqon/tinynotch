import SwiftUI

// MARK: - 017 Калькулятор

enum CalcEngine {
    static func evaluate(_ raw: String) -> Double? {
        var expr = raw
        expr = expr.replacingOccurrences(of: ",", with: ".")
        expr = expr.replacingOccurrences(of: "×", with: "*")
        expr = expr.replacingOccurrences(of: "÷", with: "/")
        expr = expr.replacingOccurrences(of: "−", with: "-")
        expr = expr.replacingOccurrences(of: "^", with: "^")
        var tokens: [String] = []
        var number = ""
        for ch in expr {
            if ch.isNumber || ch == "." { number.append(ch) }
            else if "+-*/%^()".contains(ch) {
                if !number.isEmpty { tokens.append(number); number = "" }
                tokens.append(String(ch))
            } else if !ch.isWhitespace { return nil }
        }
        if !number.isEmpty { tokens.append(number) }
        guard !tokens.isEmpty else { return nil }

        let precedence: [String: Int] = ["+": 1, "-": 1, "*": 2, "/": 2, "%": 2, "^": 3]
        var output: [String] = []
        var ops: [String] = []
        var prevWasValue = false
        for token in tokens {
            if Double(token) != nil { output.append(token); prevWasValue = true }
            else if token == "(" { ops.append(token); prevWasValue = false }
            else if token == ")" {
                while let last = ops.popLast(), last != "(" { output.append(last) }
                prevWasValue = true
            } else {
                if token == "-" && !prevWasValue { output.append("0") }
                while let last = ops.last, last != "(",
                      let p = precedence[last], let c = precedence[token], p >= c {
                    output.append(ops.removeLast())
                }
                ops.append(token)
                prevWasValue = false
            }
        }
        while let last = ops.popLast() {
            if last != "(" { output.append(last) }
        }
        var stack: [Double] = []
        for token in output {
            if let value = Double(token) { stack.append(value); continue }
            guard stack.count >= 2 else { return nil }
            let right = stack.removeLast()
            let left = stack.removeLast()
            switch token {
            case "+": stack.append(left + right)
            case "-": stack.append(left - right)
            case "*": stack.append(left * right)
            case "/": stack.append(left / right)
            case "%": stack.append(left.truncatingRemainder(dividingBy: right))
            case "^": stack.append(pow(left, right))
            default: return nil
            }
        }
        return stack.count == 1 ? stack[0] : nil
    }
}

struct CalculatorTool: View {
    @ViewState private var expression = ""
    @ViewState private var history: [String] = []

    private var result: String {
        guard !expression.isEmpty else { return "" }
        if let value = CalcEngine.evaluate(expression) {
            return trimmed(value)
        }
        return "?"
    }

    private func trimmed(_ value: Double) -> String {
        let rounded = (value * 1_000_000).rounded() / 1_000_000
        return String(format: "%.6g", rounded)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField(L("2+2*3"), text: $expression)
                .textFieldStyle(.roundedBorder)
                .font(.system(.title3, design: .monospaced))
                .onSubmit { commit() }
            HStack {
                Text("= \(result)").font(.title2.weight(.semibold)).textSelection(.enabled)
                Spacer()
                Button(L("Записать")) { commit() }.buttonStyle(.bordered).controlSize(.small)
            }
            ForEach(Array(history.enumerated()), id: \.offset) { pair in
                Text(pair.element).font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
            }
        }
    }

    private func commit() {
        guard let value = CalcEngine.evaluate(expression) else { return }
        history.insert("\(expression) = \(trimmed(value))", at: 0)
        if history.count > 8 { history.removeLast() }
    }
}

// MARK: - 018 Конвертер единиц

private struct UnitCategory {
    let name: String
    let units: [(name: String, factor: Double)]
}

private let unitCategories: [UnitCategory] = [
    UnitCategory(name: "Длина", units: [
        ("км", 1000), ("м", 1), ("см", 0.01), ("мм", 0.001),
        ("миля", 1609.344), ("фут", 0.3048), ("дюйм", 0.0254), ("ярд", 0.9144),
    ]),
    UnitCategory(name: "Вес", units: [
        ("т", 1000), ("кг", 1), ("г", 0.001), ("мг", 0.000001),
        ("фунт", 0.45359237), ("унция", 0.028349523),
    ]),
    UnitCategory(name: "Объём", units: [
        ("л", 1), ("мл", 0.001), ("м³", 1000), ("галлон US", 3.785412),
    ]),
]

struct UnitConvertTool: View {
    @ViewState private var categoryIndex = 0
    @ViewState private var fromIndex = 0
    @ViewState private var toIndex = 1
    @ViewState private var value = "1"

    private var category: UnitCategory { unitCategories[categoryIndex] }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker(L("Категория"), selection: $categoryIndex) {
                ForEach(unitCategories.indices, id: \.self) { index in
                    Text(unitCategories[index].name).tag(index)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: categoryIndex) { _ in fromIndex = 0; toIndex = 1 }

            HStack(spacing: 8) {
                TextField(L("Значение"), text: $value).textFieldStyle(.roundedBorder)
                Picker("", selection: $fromIndex) {
                    ForEach(category.units.indices, id: \.self) { Text(category.units[$0].name).tag($0) }
                }.labelsHidden().frame(width: 110)
                Image(systemName: "arrow.right").foregroundStyle(.secondary)
                Picker("", selection: $toIndex) {
                    ForEach(category.units.indices, id: \.self) { Text(category.units[$0].name).tag($0) }
                }.labelsHidden().frame(width: 110)
            }
            ToolCopyRow(text: converted)
        }
    }

    private var converted: String {
        guard let amount = Double(value.replacingOccurrences(of: ",", with: ".")) else { return "—" }
        let base = amount * category.units[fromIndex].factor
        let result = base / category.units[toIndex].factor
        return String(format: "%.6g %@", result, category.units[toIndex].name)
    }
}

// MARK: - 019 Курс валют (кэш)

private let currencyRates: [String: Double] = [
    "USD": 1, "EUR": 0.92, "RUB": 92.5, "KZT": 470, "GBP": 0.79,
    "CNY": 7.1, "TRY": 34, "AED": 3.67, "JPY": 151,
]

struct CurrencyTool: View {
    @ViewState private var amount = "100"
    @ViewState private var from = "USD"
    @ViewState private var to = "RUB"

    private var codes: [String] { currencyRates.keys.sorted() }

    private var converted: String {
        guard let value = Double(amount.replacingOccurrences(of: ",", with: ".")),
              let fromRate = currencyRates[from], let toRate = currencyRates[to] else { return "—" }
        let result = value / fromRate * toRate
        return String(format: "%.2f %@", result, to)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                TextField(L("Сумма"), text: $amount).textFieldStyle(.roundedBorder)
                Picker("", selection: $from) { ForEach(codes, id: \.self) { Text($0).tag($0) } }.labelsHidden()
                Image(systemName: "arrow.right").foregroundStyle(.secondary)
                Picker("", selection: $to) { ForEach(codes, id: \.self) { Text($0).tag($0) } }.labelsHidden()
            }
            ToolCopyRow(text: converted)
            Text(L("Курсы кэшированы, обновлю по сети позже"))
                .font(.caption2).foregroundStyle(.secondary)
        }
    }
}

// MARK: - 020 Проценты

struct PercentTool: View {
    @ViewState private var price = ""
    @ViewState private var percent = ""

    private var rows: [(String, String)] {
        guard let p = Double(price.replacingOccurrences(of: ",", with: ".")),
              let pct = Double(percent.replacingOccurrences(of: ",", with: ".")) else { return [] }
        let delta = p * pct / 100
        return [
            (L("Скидка") + " \(Int(pct))%", String(format: "%.2f", p - delta)),
            (L("Наценка") + " \(Int(pct))%", String(format: "%.2f", p + delta)),
            (L("Чаевые") + " \(Int(pct))%", String(format: "%.2f", p + delta)),
            (L("НДС") + " \(Int(pct))%", String(format: "%.2f", p + delta)),
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                TextField(L("Цена"), text: $price).textFieldStyle(.roundedBorder)
                TextField(L("%"), text: $percent).textFieldStyle(.roundedBorder).frame(width: 60)
            }
            ForEach(Array(rows.enumerated()), id: \.offset) { pair in
                HStack {
                    Text(pair.element.0).font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Text(pair.element.1).font(.system(.caption, design: .monospaced))
                }
            }
        }
    }
}

// MARK: - 021 Кредитный калькулятор

struct LoanTool: View {
    @ViewState private var amount = ""
    @ViewState private var rate = ""
    @ViewState private var months = ""

    private var result: (payment: String, total: String) {
        guard let principal = Double(amount.replacingOccurrences(of: ",", with: ".")),
              let annual = Double(rate.replacingOccurrences(of: ",", with: ".")),
              let term = Int(months), term > 0, principal > 0 else { return ("—", "—") }
        let monthlyRate = annual / 100 / 12
        let payment: Double
        if monthlyRate == 0 {
            payment = principal / Double(term)
        } else {
            let factor = pow(1 + monthlyRate, Double(term))
            payment = principal * monthlyRate * factor / (factor - 1)
        }
        return (String(format: "%.2f", payment), String(format: "%.2f", payment * Double(term)))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                TextField(L("Сумма"), text: $amount).textFieldStyle(.roundedBorder)
                TextField(L("% в год"), text: $rate).textFieldStyle(.roundedBorder).frame(width: 80)
                TextField(L("Месяцев"), text: $months).textFieldStyle(.roundedBorder).frame(width: 80)
            }
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L("Платёж в месяц")).font(.caption2).foregroundStyle(.secondary)
                    Text(result.payment).font(.headline).textSelection(.enabled)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(L("Всего выплат")).font(.caption2).foregroundStyle(.secondary)
                    Text(result.total).font(.headline).textSelection(.enabled)
                }
            }
        }
    }
}

// MARK: - 022 Монетка и кубик

struct RandomPickTool: View {
    @ViewState private var result = ""
    @ViewState private var from = 1
    @ViewState private var to = 100

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Button(L("Монетка")) { result = Bool.random() ? L("Орёл") : L("Решка") }
                Button(L("Кубик")) { result = "🎲 \(Int.random(in: 1...6))" }
                Button(L("Число")) { result = "\(Int.random(in: from...max(from, to)))" }
            }.buttonStyle(.bordered).controlSize(.small)
            Stepper(value: $from, in: 1...9999) { Text(L("От") + " \(from)") }
            Stepper(value: $to, in: 1...9999) { Text(L("До") + " \(to)") }
            Text(result.isEmpty ? "—" : result).font(.title2.weight(.semibold))
                .frame(maxWidth: .infinity).textSelection(.enabled)
        }
    }
}

// MARK: - 023 Случайный выбор из списка

struct RandomFromListTool: View {
    @ViewState private var list = ""
    @ViewState private var picked = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextEditor(text: $list).frame(minHeight: 90)
                .font(.system(.caption, design: .monospaced))
                .scrollContentBackground(.hidden)
                .background(.quinary, in: RoundedRectangle(cornerRadius: 8))
            Button(L("Кому повезёт")) { roll() }.buttonStyle(.bordered).controlSize(.small)
            Text(picked.isEmpty ? "—" : picked).font(.title2.weight(.semibold)).textSelection(.enabled)
        }
    }

    private func roll() {
        let items = list.split(whereSeparator: { $0.isNewline || $0 == "," }).map(String.init)
        guard !items.isEmpty else { picked = L("Список пуст"); return }
        picked = items.randomElement() ?? ""
    }
}

// MARK: - 026 HEX ↔ RGB

struct HexRgbTool: View {
    @ViewState private var hex = "#FF7A00"

    private var rgb: (r: Int, g: Int, b: Int)? {
        var value = hex.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "#", with: "")
        if value.count == 3 {
            value = value.map { "\($0)\($0)" }.joined()
        }
        guard value.count == 6, let number = UInt32(value, radix: 16) else { return nil }
        return (Int((number >> 16) & 255), Int((number >> 8) & 255), Int(number & 255))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ToolInOut(placeholder: L("#RRGGBB"), input: $hex)
            if let rgb {
                HStack(spacing: 10) {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color(red: Double(rgb.r) / 255, green: Double(rgb.g) / 255, blue: Double(rgb.b) / 255))
                        .frame(width: 34, height: 34)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("R \(rgb.r) · G \(rgb.g) · B \(rgb.b)").font(.system(.caption, design: .monospaced))
                        Text("rgb(\(rgb.r), \(rgb.g), \(rgb.b))").font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(L("Копировать")) { ToolClipboard.copy("rgb(\(rgb.r), \(rgb.g), \(rgb.b))") }
                        .buttonStyle(.bordered).controlSize(.small)
                }
            } else {
                Text(L("Не похоже на #RRGGBB")).font(.caption2).foregroundStyle(.red)
            }
        }
    }
}

// MARK: - 084 Мировые часы

struct WorldClockTool: View {
    private let cities: [(name: String, zone: String)] = [
        ("Москва", "Europe/Moscow"), ("Алматы", "Asia/Almaty"), ("Лондон", "Europe/London"),
        ("Нью-Йорк", "America/New_York"), ("Токио", "Asia/Tokyo"), ("Дубай", "Asia/Dubai"),
    ]

    var body: some View {
        TimelineView(.everyMinute) { context in
            VStack(alignment: .leading, spacing: 6) {
                ForEach(cities, id: \.name) { city in
                    HStack {
                        Text(city.name)
                        Spacer()
                        Text(time(in: city.zone, at: context.date))
                            .font(.system(.title3, design: .monospaced))
                    }
                }
            }
        }
    }

    private func time(in zone: String, at date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeZone = TimeZone(identifier: zone) ?? .current
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
}

// MARK: - 099 Часовые пояса

struct TzConvertTool: View {
    @ViewState private var pickedDate = Date()
    @ViewState private var baseZone = "Europe/Moscow"

    private let zones: [String] = [
        "Europe/Moscow", "Asia/Almaty", "Europe/London", "Europe/Berlin",
        "America/New_York", "America/Los_Angeles", "Asia/Tokyo", "Asia/Dubai", "UTC",
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                DatePicker(L("Когда"), selection: $pickedDate).labelsHidden()
                Picker("", selection: $baseZone) {
                    ForEach(zones, id: \.self) { Text($0).tag($0) }
                }.labelsHidden().frame(width: 150)
            }
            ForEach(zones, id: \.self) { zone in
                HStack {
                    Text(zone)
                        .font(.caption)
                        .foregroundStyle(zone == baseZone ? .primary : .secondary)
                    Spacer()
                    Text(time(in: zone))
                        .font(.system(.caption, design: .monospaced))
                        .fontWeight(zone == baseZone ? .semibold : .regular)
                }
            }
        }
    }

    private func time(in zone: String) -> String {
        let formatter = DateFormatter()
        formatter.timeZone = TimeZone(identifier: zone) ?? .current
        formatter.dateFormat = "EEE dd MMM HH:mm"
        return formatter.string(from: pickedDate)
    }
}
