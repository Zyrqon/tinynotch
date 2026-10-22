import SwiftUI
import AppKit

// MARK: - 092 2048

private struct Game2048 {
    var grid: [[Int]] = Array(repeating: Array(repeating: 0, count: 4), count: 4)
    var score = 0

    mutating func spawn() {
        var empties: [(Int, Int)] = []
        for row in 0..<4 { for col in 0..<4 where grid[row][col] == 0 { empties.append((row, col)) } }
        guard let cell = empties.randomElement() else { return }
        grid[cell.0][cell.1] = Int.random(in: 0...9) == 0 ? 4 : 2
    }

    mutating func move(_ direction: Int) {
        let before = grid
        for index in 0..<4 {
            var line: [Int] = []
            for position in 0..<4 {
                let value: Int
                switch direction {
                case 0: value = grid[position][index]
                case 1: value = grid[position][3 - index]
                case 2: value = grid[index][position]
                default: value = grid[index][3 - position]
                }
                line.append(value)
            }
            line = collapse(line)
            for position in 0..<4 {
                let value = line[position]
                switch direction {
                case 0: grid[position][index] = value
                case 1: grid[position][3 - index] = value
                case 2: grid[index][position] = value
                default: grid[index][3 - position] = value
                }
            }
        }
        if grid != before { spawn() }
    }

    private func collapse(_ input: [Int]) -> [Int] {
        var values = input.filter { $0 != 0 }
        var result: [Int] = []
        var index = 0
        while index < values.count {
            if index + 1 < values.count && values[index] == values[index + 1] {
                result.append(values[index] * 2)
                index += 2
            } else {
                result.append(values[index])
                index += 1
            }
        }
        while result.count < 4 { result.append(0) }
        return result
    }
}

struct Game2048Tool: View {
    @ViewState private var game = Game2048()
    @ViewState private var colors: [Int: Color] = [2: .orange.opacity(0.5), 4: .orange, 8: .red.opacity(0.7),
                                               16: .red, 32: .purple.opacity(0.7), 64: .purple, 128: .blue.opacity(0.6)]

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text(L("Очки: ") + "\(game.score)").font(.caption)
                Spacer()
                Button(L("Заново")) { newGame() }.buttonStyle(.bordered).controlSize(.mini)
            }
            VStack(spacing: 4) {
                ForEach(0..<4, id: \.self) { row in
                    HStack(spacing: 4) {
                        ForEach(0..<4, id: \.self) { col in
                            let value = game.grid[row][col]
                            ZStack {
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(value == 0 ? Color.secondary.opacity(0.15) : (colors[value] ?? .pink))
                                Text(value == 0 ? "" : String(value))
                                    .font(.system(size: 14, weight: .bold, design: .rounded))
                                    .foregroundStyle(.white)
                            }
                            .frame(height: 44)
                        }
                    }
                }
            }
            HStack {
                arrowButton("arrow.up", 0)
                HStack(spacing: 6) {
                    arrowButton("arrow.left", 1)
                    arrowButton("arrow.down", 2)
                    arrowButton("arrow.right", 3)
                }
            }.frame(maxWidth: .infinity)
        }
        .onAppear { newGame() }
    }

    private func arrowButton(_ icon: String, _ direction: Int) -> some View {
        Button { game.move(direction) } label: {
            Image(systemName: icon).frame(width: 34, height: 26)
        }.buttonStyle(.bordered).controlSize(.small)
    }

    private func newGame() {
        game = Game2048()
        game.spawn()
        game.spawn()
    }
}

// MARK: - 093 Змейка

private struct SnakePoint: Equatable {
    var row: Int
    var col: Int
}

struct SnakeTool: View {
    @ViewState private var cells: [SnakePoint] = [SnakePoint(row: 5, col: 5)]
    @ViewState private var food = SnakePoint(row: 2, col: 8)
    @ViewState private var direction = SnakePoint(row: 0, col: 1)
    @ViewState private var score = 0
    @ViewState private var gameOver = false
    @ViewState private var timer: Timer?
    private let size = 12

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text(L("Счёт: ") + "\(score)").font(.caption)
                Spacer()
                if gameOver { Text(L("Конец")).font(.caption).foregroundStyle(.red) }
                Button(gameOver ? L("Заново") : L("Старт")) { start() }
                    .buttonStyle(.bordered).controlSize(.mini)
            }
            VStack(spacing: 2) {
                ForEach(0..<size, id: \.self) { row in
                    HStack(spacing: 2) {
                        ForEach(0..<size, id: \.self) { col in
                            let point = SnakePoint(row: row, col: col)
                            RoundedRectangle(cornerRadius: 2)
                                .fill(color(for: point))
                                .frame(height: 14)
                        }
                    }
                }
            }
            HStack(spacing: 6) {
                dirButton("arrow.up", SnakePoint(row: -1, col: 0))
                dirButton("arrow.left", SnakePoint(row: 0, col: -1))
                dirButton("arrow.down", SnakePoint(row: 1, col: 0))
                dirButton("arrow.right", SnakePoint(row: 0, col: 1))
            }
        }
        .onDisappear { timer?.invalidate(); timer = nil }
    }

    private func color(for point: SnakePoint) -> Color {
        if point == food { return .red }
        if cells.contains(point) { return .green }
        return .secondary.opacity(0.12)
    }

    private func dirButton(_ icon: String, _ newDirection: SnakePoint) -> some View {
        Button { direction = newDirection } label: {
            Image(systemName: icon).frame(width: 30, height: 22)
        }.buttonStyle(.bordered).controlSize(.small)
    }

    private func start() {
        cells = [SnakePoint(row: 5, col: 5)]
        direction = SnakePoint(row: 0, col: 1)
        score = 0
        gameOver = false
        placeFood()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { _ in step() }
    }

    private func placeFood() {
        food = SnakePoint(row: Int.random(in: 0..<size), col: Int.random(in: 0..<size))
    }

    private func step() {
        guard !gameOver else { return }
        let head = cells[0]
        let next = SnakePoint(row: head.row + direction.row, col: head.col + direction.col)
        guard next.row >= 0, next.col >= 0, next.row < size, next.col < size, !cells.contains(next) else {
            gameOver = true
            timer?.invalidate()
            timer = nil
            return
        }
        cells.insert(next, at: 0)
        if next == food {
            score += 1
            placeFood()
        } else {
            cells.removeLast()
        }
    }
}

// MARK: - 094 Сапёр

private struct MineCell: Identifiable {
    let id: Int
    var row: Int
    var col: Int
    var isMine = false
    var isRevealed = false
    var isFlagged = false
    var neighbors = 0
}

struct MinesTool: View {
    @ViewState private var cells: [MineCell] = []
    @ViewState private var exploded = false
    private let side = 8
    private let mines = 10

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text(L("Осталось мин: ") + "\(mines - cells.filter { $0.isFlagged }.count)").font(.caption)
                Spacer()
                Button(L("Заново")) { newGame() }.buttonStyle(.bordered).controlSize(.mini)
            }
            if exploded { Text(L("Бум!")).font(.caption).foregroundStyle(.red) }
            VStack(spacing: 2) {
                ForEach(0..<side, id: \.self) { row in
                    HStack(spacing: 2) {
                        ForEach(0..<side, id: \.self) { col in
                            if let index = cellIndex(row: row, col: col) {
                                cellButton(cells[index])
                            }
                        }
                    }
                }
            }
        }
        .onAppear { newGame() }
    }

    private func cellIndex(row: Int, col: Int) -> Int? {
        cells.firstIndex { $0.row == row && $0.col == col }
    }

    private func cellButton(_ cell: MineCell) -> some View {
        Button {
            if cell.isRevealed || cell.isFlagged { return }
            if cell.isMine { exploded = true; revealAll() } else { reveal(cell.id) }
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 3)
                    .fill(cell.isRevealed ? Color.secondary.opacity(0.1) : Color.secondary.opacity(0.35))
                if cell.isFlagged {
                    Image(systemName: "flag.fill").font(.caption2)
                } else if cell.isRevealed && cell.neighbors > 0 {
                    Text("\(cell.neighbors)").font(.system(size: 10, weight: .bold))
                }
            }
            .frame(width: 30, height: 30)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(L("Флажок")) {
                if let index = cells.firstIndex(where: { $0.id == cell.id }) {
                    cells[index].isFlagged.toggle()
                }
            }
        }
    }

    private func newGame() {
        exploded = false
        var generated: [MineCell] = []
        for row in 0..<side { for col in 0..<side {
            generated.append(MineCell(id: generated.count, row: row, col: col))
        } }
        var placed = 0
        while placed < mines {
            let index = Int.random(in: 0..<generated.count)
            if !generated[index].isMine {
                generated[index].isMine = true
                placed += 1
            }
        }
        for index in generated.indices {
            generated[index].neighbors = neighbors(of: generated[index]).filter { $0.isMine }.count
        }
        cells = generated
    }

    private func neighbors(of cell: MineCell) -> [MineCell] {
        cells.filter { other in
            abs(other.row - cell.row) <= 1 && abs(other.col - cell.col) <= 1 && other.id != cell.id
        }
    }

    private func reveal(_ id: Int) {
        guard let index = cells.firstIndex(where: { $0.id == id }), !cells[index].isRevealed else { return }
        cells[index].isRevealed = true
        if cells[index].neighbors == 0 && !cells[index].isMine {
            for neighbor in neighbors(of: cells[index]) { reveal(neighbor.id) }
        }
    }

    private func revealAll() {
        for index in cells.indices { cells[index].isRevealed = true }
    }
}

// MARK: - 095 Тамагочи

private struct PetState: Codable {
    var name: String = "Байт"
    var fed: Double = 0.8
    var happy: Double = 0.8
    var lastSeen: Date = Date()
}

struct TamagotchiTool: View {
    @ViewState private var pet: PetState = {
        if let data = FileManager.default.contents(atPath: ToolStorage.file("pet.json").path),
           let saved = try? JSONDecoder().decode(PetState.self, from: data) {
            var pet = saved
            let hours = max(Date().timeIntervalSince(saved.lastSeen) / 3600, 0)
            pet.fed = max(pet.fed - hours * 0.05, 0.05)
            pet.happy = max(pet.happy - hours * 0.05, 0.05)
            pet.lastSeen = Date()
            return pet
        }
        return PetState()
    }()

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: moodIcon).font(.system(size: 42)).foregroundStyle(moodColor)
            Text(pet.name).font(.headline)
            meter(L("Сытость"), pet.fed)
            meter(L("Настроение"), pet.happy)
            HStack(spacing: 8) {
                Button(L("Покормить")) { pet.fed = min(pet.fed + 0.2, 1); save() }
                Button(L("Поиграть")) { pet.happy = min(pet.happy + 0.2, 1); save() }
            }.buttonStyle(.bordered).controlSize(.small)
        }
        .onDisappear { save() }
    }

    private var moodIcon: String {
        pet.fed > 0.4 && pet.happy > 0.4 ? "cat.fill" : "cat"
    }

    private var moodColor: Color {
        pet.fed > 0.4 && pet.happy > 0.4 ? .orange : .secondary
    }

    private func meter(_ title: String, _ value: Double) -> some View {
        HStack {
            Text(title).font(.caption2).foregroundStyle(.secondary)
            ProgressView(value: value).progressViewStyle(.linear)
        }
    }

    private func save() {
        pet.lastSeen = Date()
        let data = (try? JSONEncoder().encode(pet)) ?? Data()
        try? data.write(to: ToolStorage.file("pet.json"))
    }
}

// MARK: - 096 Блокировщик сайтов

struct SiteBlockerTool: View {
    @ViewState private var domains = ""
    @ViewState private var status = ""

    private let marker = "# tinynotch-block"

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextEditor(text: $domains).frame(minHeight: 70)
                .font(.system(.caption, design: .monospaced))
                .scrollContentBackground(.hidden)
                .background(.quinary, in: RoundedRectangle(cornerRadius: 8))
            HStack(spacing: 6) {
                Button(L("Заблокировать")) { block(true) }
                Button(L("Разблокировать")) { block(false) }
            }.buttonStyle(.bordered).controlSize(.small)
            Text(status).font(.caption)
            Text(L("macOS спросит пароль администратора: правится /etc/hosts"))
                .font(.caption2).foregroundStyle(.secondary)
        }
    }

    private func block(_ on: Bool) {
        let list = domains.split(whereSeparator: { $0.isNewline || $0 == " " })
            .map(String.init).filter { !$0.isEmpty }
        guard !list.isEmpty else { status = L("Впиши домены"); return }
        var lines: [String] = []
        if on {
            lines.append(marker)
            lines.append(contentsOf: list.map { "127.0.0.1 " + $0 })
        }
        let blockFile = ToolStorage.file("hosts.block")
        try? lines.joined(separator: "\n").write(to: blockFile, atomically: true, encoding: .utf8)
        let shell = on
            ? "cat " + blockFile.path + " | sudo tee -a /etc/hosts >/dev/null"
            : "sudo sed /" + marker + "/,+999999d /etc/hosts > /tmp/hosts.new && sudo mv /tmp/hosts.new /etc/hosts"
        let appleScript = "do shell script \"" + shell + "\" with administrator privileges"
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Shell.run("osascript -e '" + appleScript + "'")
            DispatchQueue.main.async {
                status = result.isEmpty ? (on ? L("Заблокировано") : L("Разблокировано")) : result
            }
        }
    }
}

// MARK: - 097 Статистика фокуса

struct PomodoroStatsTool: View {
    @ViewState private var sessions = Int(ToolStorage.load("pomodoro.count") ?? "0") ?? 0

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L("Всего помодоро")).font(.caption).foregroundStyle(.secondary)
            Text("\(sessions)").font(.system(size: 40, design: .rounded).weight(.bold))
            Text(L("25 минут фокуса каждое. Продолжай")).font(.caption2).foregroundStyle(.secondary)
        }
    }
}

// MARK: - 098 Горячие клавиши

struct HotkeyCheatTool: View {
    private let rows: [(String, String)] = [
        ("⌘ Space", L("Поиск (Spotlight)")),
        ("⌘ Tab", L("Переключение приложений")),
        ("⌘ C / ⌘ V", L("Копировать / вставить")),
        ("⌘ Shift 4", L("Скриншот области")),
        ("⌘ Shift 5", L("Запись экрана")),
        ("⌃ ← / →", L("Смена рабочих столов")),
        ("⌘ Option Esc", L("Принудительно закрыть приложение")),
        ("⌘ H", L("Скрыть окно")),
        ("⌘ W", L("Закрыть вкладку")),
        ("⌃ ⌘ Q", L("Заблокировать экран")),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(rows.enumerated()), id: \.offset) { pair in
                HStack {
                    Text(pair.element.0).font(.system(.caption, design: .monospaced))
                    Spacer()
                    Text(pair.element.1).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}

// MARK: - 099 Размеры одежды

struct SizeConvertTool: View {
    @ViewState private var category = 0

    private let shirts: [(String, String, String)] = [
        ("XS", "42-44", "32-34"), ("S", "44-46", "34-36"), ("M", "46-48", "36-38"),
        ("L", "48-50", "38-40"), ("XL", "50-52", "40-42"),
    ]
    private let shoes: [(String, String, String)] = [
        ("36", "22.5 см", "US 4"), ("38", "24 см", "US 5.5"), ("40", "25.5 см", "US 7"),
        ("41", "26 см", "US 8"), ("42", "27 см", "US 9"), ("44", "28.5 см", "US 10.5"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker(L("Категория"), selection: $category) {
                Text(L("Одежда")).tag(0)
                Text(L("Обувь")).tag(1)
            }.pickerStyle(.segmented)
            HStack {
                Text("RU").font(.caption2).foregroundStyle(.secondary).frame(width: 60)
                Text("EU/см").font(.caption2).foregroundStyle(.secondary).frame(width: 60)
                Text("US").font(.caption2).foregroundStyle(.secondary).frame(width: 60)
            }
            ForEach(category == 0 ? shirts : shoes, id: \.0) { row in
                HStack {
                    Text(row.0).font(.caption).frame(width: 60)
                    Text(row.1).font(.caption).frame(width: 60)
                    Text(row.2).font(.caption).frame(width: 60)
                }
            }
        }
    }
}

// MARK: - 100 Умная вставка

struct PasteCleanTool: View {
    @ViewState private var status = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(L("Вставить как чистый текст")) { pasteClean() }
                .buttonStyle(.bordered).controlSize(.small)
            Text(status).font(.caption)
            Text(L("Положи курсор в поле назначения и нажми кнопку: очистим буфер и вставим"))
                .font(.caption2).foregroundStyle(.secondary)
        }
    }

    private func pasteClean() {
        guard let raw = NSPasteboard.general.string(forType: .string) else {
            status = L("В буфере нет текста"); return
        }
        var text = raw
        text = text.replacingOccurrences(of: "\u{00A0}", with: " ")
        text = text.replacingOccurrences(of: "\u{200B}", with: "")
        let lines = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let cleaned = lines.joined(separator: "\n")
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(cleaned, forType: .string)
        let source = CGEventSource(stateID: .hidSystemState)
        let down = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true)
        down?.flags = .maskCommand
        let up = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false)
        up?.flags = .maskCommand
        down?.post(tap: .cgAnnotatedSessionEventTap)
        up?.post(tap: .cgAnnotatedSessionEventTap)
        status = L("Вставил чистый текст (нужен доступ «Универсальный доступ»)")
    }
}
