import SwiftUI
import AppKit

enum ToolClipboard {
    static func copy(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
    static func paste() -> String {
        NSPasteboard.general.string(forType: .string) ?? ""
    }
}

struct ToolBox<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
            content()
        }
    }
}

struct ToolCopyRow: View {
    let text: String
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(text.isEmpty ? "—" : text)
                .font(.system(.caption, design: .monospaced))
                .lineLimit(4).textSelection(.enabled)
            Spacer(minLength: 4)
            Button(L("Копировать")) { ToolClipboard.copy(text) }
                .buttonStyle(.bordered).controlSize(.small)
                .disabled(text.isEmpty)
        }
        .padding(8)
        .background(.quinary, in: RoundedRectangle(cornerRadius: 8))
    }
}

struct ToolInOut: View {
    var placeholder: String
    @Binding var input: String
    var body: some View {
        HStack(spacing: 6) {
            Button(L("Вставить")) { input = ToolClipboard.paste() }
                .buttonStyle(.bordered).controlSize(.small)
            TextField(placeholder, text: $input, axis: .vertical).lineLimit(1...3)
                .textFieldStyle(.roundedBorder)
        }
    }
}

/// Вкладка «Инструменты»: секции-категории как панели в Blender, поиск и строки тулов.
struct ToolsTabView: View {
    @ObservedObject var model: IslandModel
    @ObservedObject var packs: ToolPackManager
    @ViewState private var query = ""
    @ViewState private var expanded: Set<String> = ["Код"]
    @ViewState private var selected: ToolID?
    @ViewState private var hovered: ToolID?

    private var categories: [String] {
        var seen: [String] = []
        for tool in ToolID.allCases where !seen.contains(tool.category) { seen.append(tool.category) }
        return seen
    }

    private func matches(_ tool: ToolID, _ q: String) -> Bool {
        tool.title.localizedCaseInsensitiveContains(q) || tool.category.localizedCaseInsensitiveContains(q)
    }

    /// Свой цвет и значок для каждой категории (как цветные вкладки в Blender).
    private func accent(for category: String) -> (icon: String, color: Color) {
        switch category {
        case "Текст": return ("textformat.123", Color.indigo)
        case "Счёт": return ("plus.forwardslash.minus", Color.yellow)
        case "Код": return ("chevron.left.forwardslash.fill", Color.teal)
        case "Медиа": return ("photo.on.rectangle.angled.fill", Color.purple)
        case "Система": return ("cpu.fill", Color.blue)
        case "Инфо": return ("info.circle.fill", Color.orange)
        case "Время": return ("clock.fill", Color.pink)
        case "Игры": return ("gamecontroller.fill", Color.green)
        default: return ("square.grid.2x2.fill", Color.secondary)
        }
    }

    private var progressFraction: Double {
        let total = max(ToolID.allCases.count, 1)
        return min(Double(ToolImplementations.count) / Double(total), 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let tool = selected {
                HStack(spacing: 9) {
                    Button { withAnimation(.smooth(duration: 0.25)) { selected = nil } } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.primary)
                            .frame(width: 24, height: 24)
                            .background(.quinary, in: RoundedRectangle(cornerRadius: 7))
                    }
                    .buttonStyle(.plain)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(tool.title).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                        Text("#\(tool.number) · \(tool.category)")
                            .font(.caption2).foregroundStyle(.tertiary)
                    }
                    Spacer()
                    statusBadge(tool)
                }
                ToolDetailView(tool: tool, packs: packs)
            } else {
                searchBar
                toolsList
            }
        }
        .padding(12)
    }

    @ViewBuilder
    private func statusBadge(_ tool: ToolID) -> some View {
        let locked = packs.baseOnly && !packs.isEnabled(tool)
        if locked {
            label(L("пак"), Color.orange)
        } else if tool.implemented {
            label(L("готово"), Color.green)
        } else {
            label(L("скоро"), Color.secondary)
        }
    }

    private func label(_ text: String, _ color: Color) -> some View {
        Text(text)
            .font(.system(size: 9.5, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(color.opacity(0.13), in: Capsule())
    }

    private var searchBar: some View {
        VStack(spacing: 7) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                TextField(L("Поиск инструмента"), text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12.5))
                Text("\(ToolImplementations.count)/\(ToolID.allCases.count)")
                    .font(.system(size: 10, design: .monospaced).weight(.medium))
                    .foregroundStyle(Color.teal)
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(Color.teal.opacity(0.12), in: Capsule())
                Button {
                    withAnimation(.smooth(duration: 0.45)) { packs.baseOnly.toggle() }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: packs.baseOnly ? "lock.fill" : "lock.open.fill")
                            .font(.system(size: 9))
                        Text(packs.baseOnly ? L("База") : L("Все"))
                    }
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(packs.baseOnly ? Color.orange : Color.teal)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(packs.baseOnly ? Color.orange.opacity(0.13) : Color.teal.opacity(0.13), in: Capsule())
                }
                .buttonStyle(.plain)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.quaternary)
                    Capsule()
                        .fill(LinearGradient(colors: [Color.teal, Color.mint],
                                             startPoint: .leading, endPoint: .trailing))
                        .frame(width: geo.size.width * progressFraction)
                }
            }
            .frame(height: 3)
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(.quinary, in: RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder private var toolsList: some View {
        let q = query.trimmingCharacters(in: .whitespaces)
        if q.isEmpty {
            ScrollView {
                VStack(spacing: 5) {
                    ForEach(categories, id: \.self) { cat in
                        categoryPanel(cat)
                    }
                }
                .padding(.bottom, 6)
            }
        } else {
            ScrollView {
                VStack(spacing: 2) {
                    ForEach(ToolID.allCases.filter { matches($0, q) }) { tool in
                        toolRow(tool)
                    }
                }
                .padding(.bottom, 6)
            }
        }
    }

    private func categoryPanel(_ category: String) -> some View {
        let tools = ToolID.allCases.filter { $0.category == category }
        let isOpen = expanded.contains(category)
        let a = accent(for: category)
        return VStack(spacing: 0) {
            Button {
                withAnimation(.smooth(duration: 0.3)) {
                    if isOpen { expanded.remove(category) } else { expanded.insert(category) }
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: a.icon)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(a.color)
                        .frame(width: 22, height: 22)
                        .background(a.color.opacity(0.15), in: RoundedRectangle(cornerRadius: 6))
                    Text(category).font(.system(size: 12, weight: .semibold))
                    Spacer()
                    Text("\(tools.count)")
                        .font(.system(size: 10, design: .monospaced).weight(.medium))
                        .foregroundStyle(a.color)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(a.color.opacity(0.12), in: Capsule())
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .rotationEffect(.degrees(isOpen ? 90 : 0))
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 10).padding(.vertical, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .background(.quinary, in: RoundedRectangle(cornerRadius: 10))
            if isOpen {
                VStack(spacing: 2) {
                    ForEach(tools) { tool in
                        toolRow(tool)
                    }
                }
                .padding(.top, 3)
                .transition(.opacity)
            }
        }
    }

    private func toolRow(_ tool: ToolID) -> some View {
        let locked = packs.baseOnly && !packs.isEnabled(tool)
        let a = accent(for: tool.category)
        return Button { withAnimation(.smooth(duration: 0.25)) { selected = tool } } label: {
            HStack(spacing: 8) {
                Image(systemName: tool.icon)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(locked ? Color.orange : (tool.implemented ? a.color : Color.secondary.opacity(0.55)))
                    .frame(width: 16)
                Text(tool.title)
                    .font(.system(size: 12))
                    .lineLimit(1)
                Spacer()
                if locked {
                    Image(systemName: "lock.fill").font(.system(size: 9, weight: .semibold)).foregroundStyle(Color.orange)
                } else if tool.implemented {
                    Circle().fill(Color.green).frame(width: 5, height: 5)
                } else {
                    Text(L("скоро"))
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(.quaternary, in: Capsule())
                }
                Text("#\(tool.number)")
                    .font(.system(size: 9.5, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(hovered == tool ? Color.primary.opacity(0.07) : Color.clear,
                        in: RoundedRectangle(cornerRadius: 8))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            if hovering { hovered = tool } else if hovered == tool { hovered = nil }
        }
    }
}

struct ToolCard: View {
    let tool: ToolID
    var locked: Bool = false
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: tool.icon)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(locked ? Color.secondary : (tool.implemented ? Color.primary : Color.secondary))
                Spacer()
                if locked {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Color.orange)
                } else {
                    Circle()
                        .fill(tool.implemented ? Color.green : Color.secondary.opacity(0.4))
                        .frame(width: 6, height: 6)
                }
            }
            Text(tool.title)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(2).multilineTextAlignment(.leading)
            Text(locked ? "пак" : "#\(tool.number)")
                .font(.caption2).foregroundStyle(.tertiary)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quinary, in: RoundedRectangle(cornerRadius: 10))
        .opacity(locked ? 0.55 : 1)
        .contentShape(RoundedRectangle(cornerRadius: 10))
    }
}

struct ToolDetailView: View {
    let tool: ToolID
    @ObservedObject var packs: ToolPackManager
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Image(systemName: tool.icon)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 30, height: 30)
                        .background(Color.accentColor.opacity(0.15), in: RoundedRectangle(cornerRadius: 8))
                    VStack(alignment: .leading, spacing: 1) {
                        Text(tool.title).font(.system(size: 14, weight: .semibold))
                        Text("#\(tool.number) · \(tool.category)")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                if packs.baseOnly && !packs.isEnabled(tool) {
                    packLockedPanel
                } else {
                    toolBody
                        .padding(10)
                        .background(.quinary, in: RoundedRectangle(cornerRadius: 10))
                }
            }
            .padding(2)
        }
    }

    @ViewBuilder private var toolBody: some View {
        switch tool {
        case .stripFormat: StripFormatTool()
        case .charCount: CharCountTool()
        case .caseConvert: CaseConvertTool()
        case .translit: TranslitTool()
        case .base64: Base64Tool()
        case .urlEncode: UrlEncodeTool()
        case .jsonFormat: JsonFormatTool()
        case .sha256: Sha256Tool()
        case .uuidGen: UuidTool()
        case .passGen: PassGenTool()
        case .unixTime: UnixTimeTool()
        case .regexTest: RegexTestTool()
        case .textDiff: TextDiffTool()
        case .loremIpsum: LoremTool()
        case .morse: MorseTool()
        case .romanNumerals: RomanTool()
        case .calculator: CalculatorTool()
        case .unitConvert: UnitConvertTool()
        case .currencyConvert: CurrencyTool()
        case .percentCalc: PercentTool()
        case .loanCalc: LoanTool()
        case .randomPick: RandomPickTool()
        case .randomFromList: RandomFromListTool()
        case .hexRgb: HexRgbTool()
        case .worldClock: WorldClockTool()
        case .tzConvert: TzConvertTool()
        case .sysMonitors: SysMonitorsTool()
        case .diskSpace: DiskSpaceTool()
        case .batteryInfo: BatteryInfoTool()
        case .uptimeInfo: UptimeInfoTool()
        case .publicIP: PublicIPTool()
        case .pingHost: PingTool()
        case .speedTest: SpeedTestTool()
        case .folderSize: FolderSizeTool()
        case .bigFiles: BigFilesTool()
        case .emptyTrash: EmptyTrashTool()
        case .caffeinate: CaffeinateTool()
        case .themeToggle: ThemeToggleTool()
        case .dndToggle: DNDToggleTool()
        case .killProcess: KillProcessTool()
        case .wifiList: WifiListTool()
        case .shotArea: ShotTool(isArea: true)
        case .shotWindow: ShotTool(isArea: false)
        case .ocrShot: OcrShotTool()
        case .micRecord: MicRecordTool()
        case .voiceNotes: MicRecordTool()
        case .imgConvertExt: ImgConvertExtTool()
        case .pdfCompress: PdfCompressTool()
        case .pdfMerge: PdfMergeTool()
        case .pdfSplit: PdfSplitTool()
        case .imgRotate: ImgRotateTool()
        case .imgWatermark: ImgWatermarkTool()
        case .videoDownload: VideoDownloadTool()
        case .videoAudio: VideoAudioTool()
        case .videoGif: VideoGifTool()
        case .videoCompress: VideoCompressTool()
        case .batchRename: BatchRenameTool()
        case .gitStatus: GitStatusTool()
        case .gitLog: GitLogTool()
        case .todoCount: TodoCountTool()
        case .openEditor: OpenEditorTool()
        case .localServer: LocalServerTool()
        case .portWho: PortWhoTool()
        case .ngrokTunnel: GitDiffTool()
        case .sqlSelect: ApiTestTool()
        case .sqlFormat: EnvInfoTool()
        case .cronExplain: CronExplainTool()
        case .weatherNow: WeatherNowTool()
        case .ratesLive: RatesLiveTool()
        case .quickSticky: QuickStickyTool()
        case .shoppingList: ShoppingListTool()
        case .rssFeed: RssFeedTool()
        case .hnFeed: HnFeedTool()
        case .birthdaysNear: BirthdaysNearTool()
        case .tgSelf: TgSelfTool()
        case .scratchpad: ScratchpadTool()
        case .sysSchedule: SysScheduleTool()
        case .pomodoro: PomodoroTool()
        case .metronome: MetronomeTool()
        case .stopwatch: StopwatchTool()
        case .countdownDate: CountdownDateTool()
        case .backToTask: BackToTaskTool()
        case .stretchReminder: StretchReminderTool()
        case .waterCounter: WaterCounterTool()
        case .breathe: BreatheTool()
        case .quoteOfDay: QuoteOfDayTool()
        case .jokeOfDay: JokeOfDayTool()
        case .game2048: Game2048Tool()
        case .snake: SnakeTool()
        case .mines: MinesTool()
        case .tamagotchi: TamagotchiTool()
        case .siteBlocker: SiteBlockerTool()
        case .pomodoroStats: PomodoroStatsTool()
        case .hotkeyCheat: HotkeyCheatTool()
        case .sizeConvert: SizeConvertTool()
        case .pasteClean: PasteCleanTool()
        case .qrGen: QrGenTool()
        case .colorPicker: ColorPickerTool()
        case .paletteImg: PaletteImgTool()
        case .screenRuler: ScreenRulerTool()
        default: ToolComingView(tool: tool)
        }
    }

    @ViewState private var packStatus = ""

    private var packLockedPanel: some View {
        VStack(spacing: 10) {
            Image(systemName: "lock.fill")
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(.secondary)
            Text(L("Инструмент в паке")).font(.system(size: 14, weight: .semibold))
            Text(L("Пак: ") + (packs.pack(for: tool)?.name ?? L("Дополнение")))
                .font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 8) {
                Button {
                    packStatus = L("Устанавливаю…")
                    packs.installFromWeb(id: packs.pack(for: tool)?.id ?? "") { ok in
                        packStatus = ok ? L("Пак установлен") : L("Не скачался, попробуй через сайт")
                    }
                } label: {
                    Label(L("Установить пак"), systemImage: "arrow.down.circle")
                }
                .buttonStyle(.borderedProminent).controlSize(.small)
                Button { packs.openSite() } label: {
                    Label(L("Сайт"), systemImage: "safari")
                }
                .buttonStyle(.bordered).controlSize(.small)
                Button { packs.openPacksFolder() } label: {
                    Label(L("Папка"), systemImage: "folder")
                }
                .buttonStyle(.bordered).controlSize(.small)
            }
            if !packStatus.isEmpty {
                Text(packStatus).font(.caption2).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .transition(.opacity)
    }
}
