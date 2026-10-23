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
/// Вкладка «Инструменты». Написана с нуля.
/// Ключ к плавности: ховер живёт внутри карточки (перерисовывается одна карточка,
/// а не вся вкладка), у вкладки нет анимаций на всё поддерево, а высота холста
/// не анимируется вовсе (см. IslandRootView).
struct ToolsTabView: View {
    @ObservedObject var model: IslandModel
    @ObservedObject var packs: ToolPackManager
    @ViewState private var query = ""
    @ViewState private var activeCategory: String? = nil
    @ViewState private var selected: ToolID?

    private var categories: [String] {
        var seen: [String] = []
        for tool in ToolID.allCases where !seen.contains(tool.category) { seen.append(tool.category) }
        return seen
    }

    private func matches(_ tool: ToolID, _ q: String) -> Bool {
        tool.title.localizedCaseInsensitiveContains(q) || tool.category.localizedCaseInsensitiveContains(q)
    }

    /// Свой цвет и значок для каждой категории.
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
        Group {
            if let tool = selected {
                VStack(alignment: .leading, spacing: 10) {
                    detailHeader(tool)
                    ToolDetailView(tool: tool, packs: packs)
                }
                .transition(.opacity)
            } else {
                VStack(alignment: .leading, spacing: 9) {
                    searchBar
                    toolsList
                }
                .transition(.opacity)
            }
        }
        .padding(10)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            ToolsResizeGrip(model: model).padding(.top, 4).padding(.bottom, 3)
        }
        .animation(.easeOut(duration: 0.2), value: selected)
    }

    private func detailHeader(_ tool: ToolID) -> some View {
        HStack(spacing: 9) {
            Button {
                withAnimation(.easeOut(duration: 0.2)) { selected = nil }
            } label: {
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
            ToolsStatusBadge(tool: tool, packs: packs)
        }
    }

    private var searchBar: some View {
        VStack(spacing: 5) {
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
                    packs.baseOnly.toggle()
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
            .frame(height: 2)
        }
        .padding(.horizontal, 8).padding(.vertical, 5)
        .background(.quinary, in: RoundedRectangle(cornerRadius: 7))
    }

    private var toolsList: some View {
        let q = query.trimmingCharacters(in: .whitespaces)
        let list: [ToolID] = {
            if !q.isEmpty { return ToolID.allCases.filter { matches($0, q) } }
            if let cat = activeCategory { return ToolID.allCases.filter { $0.category == cat } }
            return Array(ToolID.allCases)
        }()
        return ScrollView {
            LazyVStack(alignment: .leading, spacing: 9) {
                if q.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            chip(L("Все"), nil)
                            ForEach(categories, id: \.self) { chip($0, $0) }
                        }
                        .padding(.horizontal, 2)
                        .padding(.vertical, 2)
                    }
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 118, maximum: 170), spacing: 8)],
                          alignment: .leading, spacing: 8) {
                    ForEach(list) { tool in
                        ToolsCard(tool: tool, packs: packs,
                                  icon: accent(for: tool.category).icon,
                                  color: accent(for: tool.category).color) {
                            withAnimation(.easeOut(duration: 0.2)) { selected = tool }
                        }
                    }
                }
            }
            .padding(.bottom, 8)
        }
    }

    private func chip(_ title: String, _ category: String?) -> some View {
        let isActive = activeCategory == category
        let tint = category.map { accent(for: $0).color } ?? Color.secondary
        return Button {
            activeCategory = category
        } label: {
            HStack(spacing: 4) {
                if let category {
                    Image(systemName: accent(for: category).icon)
                        .font(.system(size: 8.5, weight: .semibold))
                }
                Text(title)
            }
            .font(.system(size: 10.5, weight: .medium))
            .foregroundStyle(isActive ? Color.white : Color.primary.opacity(0.75))
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(isActive ? AnyShapeStyle(tint) : AnyShapeStyle(.quinary), in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// Карточка инструмента. Ховер живёт здесь, внутри карточки: наведение
/// перерисовывает только её, а не всю вкладку.
private struct ToolsCard: View {
    let tool: ToolID
    let packs: ToolPackManager
    let icon: String
    let color: Color
    let open: () -> Void
    @ViewState private var hovered = false

    var body: some View {
        Button(action: open) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 5) {
                    Image(systemName: icon)
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundStyle(color)
                    Spacer()
                    ToolsStatusBadge(tool: tool, packs: packs)
                }
                Text(tool.title)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(2).multilineTextAlignment(.leading)
                    .foregroundStyle(hovered ? Color.primary : Color.secondary)
                    .frame(maxWidth: .infinity, minHeight: 24, alignment: .topLeading)
                Text(tool.category)
                    .font(.system(size: 8.5, weight: .medium))
                    .foregroundStyle(color.opacity(0.8))
            }
            .padding(9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(hovered ? 0.09 : 0.05)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .animation(.easeOut(duration: 0.12), value: hovered)
    }
}

/// Бейдж статуса инструмента: «пак» / «готово» / «скоро».
private struct ToolsStatusBadge: View {
    let tool: ToolID
    let packs: ToolPackManager

    var body: some View {
        if packs.baseOnly && !packs.isEnabled(tool) {
            badge(L("пак"), Color.orange)
        } else if tool.implemented {
            badge(L("готово"), Color.green)
        } else {
            badge(L("скоро"), Color.secondary)
        }
    }

    private func badge(_ text: String, _ color: Color) -> some View {
        Text(text)
            .font(.system(size: 9.5, weight: .semibold))
            .foregroundStyle(color.opacity(0.9))
            .padding(.horizontal, 8).padding(.vertical, 5)
            .background(.quinary, in: RoundedRectangle(cornerRadius: 7))
    }
}

/// Серая полоска внизу острова: тянешь вниз — остров вытягивается, вверх — сжимается.
/// Живёт своим состоянием, ховер и тяга не перерисовывают сетку.
private struct ToolsResizeGrip: View {
    @ObservedObject var model: IslandModel
    @ViewState private var gripHovered = false
    @ViewState private var resizing = false
    @ViewState private var extraAtDragStart: CGFloat = 0

    var body: some View {
        RoundedRectangle(cornerRadius: 2.5, style: .continuous)
            .fill(Color.white.opacity(resizing ? 0.55 : gripHovered ? 0.4 : 0.25))
            .frame(width: 130, height: 5)
            .contentShape(Rectangle().inset(by: -8))
            .onHover { gripHovered = $0 }
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        if !resizing {
                            resizing = true
                            extraAtDragStart = model.toolsExtra
                        }
                        model.toolsExtra = min(420, max(0, extraAtDragStart + value.translation.height))
                    }
                    .onEnded { _ in resizing = false }
            )
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
        case .dupFinder: DupFinderTool()
        case .dnsWho: DnsWhoTool()
        case .remindLater: RemindLaterTool()
        case .imgShrink: ImgShrinkTool()
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
