import SwiftUI

/// Реестр ровно 100 инструментов островка. Каждый кейс - отдельная фича.
/// Фичи реализуются по одной (см. FEATURES_100.md); `implemented` показывает, что тул уже в коде.
enum ToolID: String, CaseIterable, Identifiable {
    case stripFormat,
    charCount,
    caseConvert,
    translit,
    base64,
    urlEncode,
    jsonFormat,
    sha256,
    uuidGen,
    passGen,
    unixTime,
    regexTest,
    textDiff,
    loremIpsum,
    morse,
    romanNumerals,
    calculator,
    unitConvert,
    currencyConvert,
    percentCalc,
    loanCalc,
    randomPick,
    randomFromList,
    qrGen,
    colorPicker,
    hexRgb,
    paletteImg,
    screenRuler,
    sysMonitors,
    diskSpace,
    batteryInfo,
    uptimeInfo,
    publicIP,
    pingHost,
    speedTest,
    folderSize,
    bigFiles,
    emptyTrash,
    caffeinate,
    themeToggle,
    dndToggle,
    killProcess,
    wifiList,
    shotArea,
    shotWindow,
    ocrShot,
    micRecord,
    voiceNotes,
    imgConvertExt,
    pdfCompress,
    pdfMerge,
    pdfSplit,
    imgRotate,
    imgWatermark,
    videoDownload,
    videoAudio,
    videoGif,
    videoCompress,
    batchRename,
    gitStatus,
    gitLog,
    todoCount,
    openEditor,
    localServer,
    portWho,
    ngrokTunnel,
    sqlSelect,
    sqlFormat,
    cronExplain,
    weatherNow,
    ratesLive,
    quickSticky,
    shoppingList,
    rssFeed,
    hnFeed,
    birthdaysNear,
    tgSelf,
    scratchpad,
    sysSchedule,
    pomodoro,
    metronome,
    stopwatch,
    countdownDate,
    worldClock,
    backToTask,
    stretchReminder,
    waterCounter,
    breathe,
    quoteOfDay,
    jokeOfDay,
    game2048,
    snake,
    mines,
    tamagotchi,
    siteBlocker,
    pomodoroStats,
    hotkeyCheat,
    sizeConvert,
    tzConvert,
    pasteClean,
    dupFinder,
    dnsWho,
    remindLater,
    imgShrink

    var id: String { rawValue }

    /// Номер в реестре 1...100 (порядок кейсов = порядок реестра).
    var number: Int { (ToolID.allCases.firstIndex(of: self) ?? 0) + 1 }

    var title: String {
        switch self {
        case .stripFormat: return L("Чистка форматирования")
        case .charCount: return L("Счётчик символов")
        case .caseConvert: return L("Регистр текста")
        case .translit: return L("Транслит RU→LAT")
        case .base64: return L("Base64")
        case .urlEncode: return L("URL-кодирование")
        case .jsonFormat: return L("JSON-форматтер")
        case .sha256: return L("SHA-256 хеш")
        case .uuidGen: return L("UUID")
        case .passGen: return L("Генератор паролей")
        case .unixTime: return L("Unix-время")
        case .regexTest: return L("Regex-тестер")
        case .textDiff: return L("Diff текстов")
        case .loremIpsum: return L("Lorem ipsum")
        case .morse: return L("Морзе")
        case .romanNumerals: return L("Римские цифры")
        case .calculator: return L("Калькулятор")
        case .unitConvert: return L("Конвертер единиц")
        case .currencyConvert: return L("Курс валют")
        case .percentCalc: return L("Проценты")
        case .loanCalc: return L("Кредитный калькулятор")
        case .randomPick: return L("Монетка и кубик")
        case .randomFromList: return L("Случайный выбор")
        case .qrGen: return L("QR-код")
        case .colorPicker: return L("Пипетка цвета")
        case .hexRgb: return L("HEX ↔ RGB")
        case .paletteImg: return L("Палитра из картинки")
        case .screenRuler: return L("Экранная линейка")
        case .sysMonitors: return L("Монитор CPU/RAM")
        case .diskSpace: return L("Место на дисках")
        case .batteryInfo: return L("Батарея")
        case .uptimeInfo: return L("Uptime")
        case .publicIP: return L("Публичный IP")
        case .pingHost: return L("Пинг")
        case .speedTest: return L("Скорость сети")
        case .folderSize: return L("Размер папки")
        case .bigFiles: return L("Большие файлы")
        case .emptyTrash: return L("Корзина")
        case .caffeinate: return L("Не спать")
        case .themeToggle: return L("Тема")
        case .dndToggle: return L("Не беспокоить")
        case .killProcess: return L("Процессы")
        case .wifiList: return L("Wi-Fi")
        case .shotArea: return L("Скриншот области")
        case .shotWindow: return L("Скриншот окна")
        case .ocrShot: return L("OCR")
        case .micRecord: return L("Запись звука")
        case .voiceNotes: return L("Диктофон")
        case .imgConvertExt: return L("Конвертер картинок+")
        case .pdfCompress: return L("Сжатие PDF")
        case .pdfMerge: return L("Слияние PDF")
        case .pdfSplit: return L("Разделение PDF")
        case .imgRotate: return L("Поворот картинки")
        case .imgWatermark: return L("Водяной знак")
        case .videoDownload: return L("Скачать видео")
        case .videoAudio: return L("Аудио из видео")
        case .videoGif: return L("GIF из видео")
        case .videoCompress: return L("Сжатие видео")
        case .batchRename: return L("Пакетное переименование")
        case .gitStatus: return L("Git-статус")
        case .gitLog: return L("Коммиты")
        case .todoCount: return L("TODO-счётчик")
        case .openEditor: return L("Открыть в редакторе")
        case .localServer: return L("Локальный сервер")
        case .portWho: return L("Порты")
        case .ngrokTunnel: return L("Git-диф")
        case .sqlSelect: return L("API-тест")
        case .sqlFormat: return L("Окружение")
        case .cronExplain: return L("Cron")
        case .weatherNow: return L("Погода")
        case .ratesLive: return L("Курсы в строке")
        case .quickSticky: return L("Стикер-заметка")
        case .shoppingList: return L("Чеклист покупок")
        case .rssFeed: return L("RSS")
        case .hnFeed: return L("Hacker News")
        case .birthdaysNear: return L("Дни рождения")
        case .tgSelf: return L("В Telegram себе")
        case .scratchpad: return L("Черновик")
        case .sysSchedule: return L("Расписание сегодня")
        case .pomodoro: return L("Помодоро")
        case .metronome: return L("Метроном")
        case .stopwatch: return L("Секундомер")
        case .countdownDate: return L("Отсчёт до даты")
        case .worldClock: return L("Мировые часы")
        case .backToTask: return L("Вернись к задаче")
        case .stretchReminder: return L("Стретчинг")
        case .waterCounter: return L("Счётчик воды")
        case .breathe: return L("Дыхание 4-7-8")
        case .quoteOfDay: return L("Цитата дня")
        case .jokeOfDay: return L("Шутка дня")
        case .game2048: return L("2048")
        case .snake: return L("Змейка")
        case .mines: return L("Сапёр")
        case .tamagotchi: return L("Тамагочи")
        case .siteBlocker: return L("Блокировщик сайтов")
        case .pomodoroStats: return L("Статистика фокуса")
        case .hotkeyCheat: return L("Горячие клавиши")
        case .sizeConvert: return L("Размеры одежды")
        case .tzConvert: return L("Часовые пояса")
        case .pasteClean: return L("Умная вставка")
        case .dupFinder: return L("Дубликаты файлов")
        case .dnsWho: return L("Сеть: DNS и whois")
        case .remindLater: return L("Напомни через N")
        case .imgShrink: return L("Сжать картинки")
        }
    }

    var icon: String {
        switch self {
        case .stripFormat: return "sparkles"
        case .charCount: return "textformat.123"
        case .caseConvert: return "characters.globe"
        case .translit: return "character.cursor.ibeam"
        case .base64: return "arrow.up.arrow.down"
        case .urlEncode: return "link"
        case .jsonFormat: return "curlybraces.square"
        case .sha256: return "number.square"
        case .uuidGen: return "qrcode"
        case .passGen: return "key.horizontal"
        case .unixTime: return "clock.badge.exclamationmark"
        case .regexTest: return "dot.scope"
        case .textDiff: return "arrow.left.arrow.right"
        case .loremIpsum: return "doc.plaintext"
        case .morse: return "waveform"
        case .romanNumerals: return "hashtag"
        case .calculator: return "plus.forwardslash.minus"
        case .unitConvert: return "scalemass"
        case .currencyConvert: return "dollarsign.circle"
        case .percentCalc: return "percent"
        case .loanCalc: return "banknote"
        case .randomPick: return "dice"
        case .randomFromList: return "circle.grid.3x3"
        case .qrGen: return "qrcode.viewfinder"
        case .colorPicker: return "eyedropper"
        case .hexRgb: return "paintpalette"
        case .paletteImg: return "photo.stack"
        case .screenRuler: return "ruler"
        case .sysMonitors: return "speedometer"
        case .diskSpace: return "internaldrive"
        case .batteryInfo: return "battery.100bolt"
        case .uptimeInfo: return "hourglass"
        case .publicIP: return "network"
        case .pingHost: return "dot.radiowaves.left.and.right"
        case .speedTest: return "gauge"
        case .folderSize: return "folder.badge.gearshape"
        case .bigFiles: return "magnifyingglass"
        case .emptyTrash: return "trash"
        case .caffeinate: return "moon.zzz.fill"
        case .themeToggle: return "circle.lefthalf.filled"
        case .dndToggle: return "moon.haze"
        case .killProcess: return "list.bullet.rectangle"
        case .wifiList: return "wifi"
        case .shotArea: return "camera.viewfinder"
        case .shotWindow: return "macwindow"
        case .ocrShot: return "doc.text.viewfinder"
        case .micRecord: return "mic.fill"
        case .voiceNotes: return "waveform.path.mic"
        case .imgConvertExt: return "photo.on.rectangle.angled"
        case .pdfCompress: return "doc.badge.arrow.up"
        case .pdfMerge: return "arrow.down.doc"
        case .pdfSplit: return "arrow.triangle.merge"
        case .imgRotate: return "scissors"
        case .imgWatermark: return "rotate.left"
        case .videoDownload: return "drop.halffull"
        case .videoAudio: return "arrow.down.circle"
        case .videoGif: return "music.note"
        case .videoCompress: return "film"
        case .batchRename: return "arrow.down.left.video"
        case .gitStatus: return "folder.gear"
        case .gitLog: return "arrow.triangle.branch"
        case .todoCount: return "number.circle"
        case .openEditor: return "text.badge.plus"
        case .localServer: return "pencil.line"
        case .portWho: return "terminal"
        case .ngrokTunnel: return "plus.forwardslash.minus"
        case .sqlSelect: return "paperplane"
        case .sqlFormat: return "cpu"
        case .cronExplain: return "chevron.left.slash.chevron.right"
        case .weatherNow: return "cloud.sun"
        case .ratesLive: return "banknote.fill"
        case .quickSticky: return "square.and.pencil"
        case .shoppingList: return "checklist"
        case .rssFeed: return "dot.radiowaves.right"
        case .hnFeed: return "newspaper"
        case .birthdaysNear: return "gift"
        case .tgSelf: return "paperplane.fill"
        case .scratchpad: return "note.text"
        case .sysSchedule: return "calendar.day.timeline.left"
        case .pomodoro: return "timer"
        case .metronome: return "metronome"
        case .stopwatch: return "stopwatch.fill"
        case .countdownDate: return "calendar.badge.clock"
        case .worldClock: return "globe"
        case .backToTask: return "arrow.uturn.left"
        case .stretchReminder: return "figure.flexibility"
        case .waterCounter: return "drop.fill"
        case .breathe: return "lungs.fill"
        case .quoteOfDay: return "quote.opening"
        case .jokeOfDay: return "face.smiling"
        case .game2048: return "square.grid.4x3.fill"
        case .snake: return "gamecontroller"
        case .mines: return "mine"
        case .tamagotchi: return "cat.fill"
        case .siteBlocker: return "eye.slash"
        case .pomodoroStats: return "chart.bar.xaxis"
        case .hotkeyCheat: return "command"
        case .sizeConvert: return "tshirt"
        case .tzConvert: return "globe.asia.australia.fill"
        case .pasteClean: return "clipboard"
        case .dupFinder: return "doc.on.doc"
        case .dnsWho: return "network"
        case .remindLater: return "bell.badge.fill"
        case .imgShrink: return "arrow.down.right.and.arrow.up.left"
        }
    }

    var category: String {
        switch self {
        case .stripFormat: return "Текст"
        case .charCount: return "Текст"
        case .caseConvert: return "Текст"
        case .translit: return "Текст"
        case .base64: return "Текст"
        case .urlEncode: return "Текст"
        case .jsonFormat: return "Текст"
        case .sha256: return "Текст"
        case .uuidGen: return "Текст"
        case .passGen: return "Текст"
        case .unixTime: return "Текст"
        case .regexTest: return "Текст"
        case .textDiff: return "Текст"
        case .loremIpsum: return "Текст"
        case .morse: return "Текст"
        case .romanNumerals: return "Текст"
        case .calculator: return "Счёт"
        case .unitConvert: return "Счёт"
        case .currencyConvert: return "Счёт"
        case .percentCalc: return "Счёт"
        case .loanCalc: return "Счёт"
        case .randomPick: return "Счёт"
        case .randomFromList: return "Счёт"
        case .qrGen: return "Счёт"
        case .colorPicker: return "Счёт"
        case .hexRgb: return "Счёт"
        case .paletteImg: return "Счёт"
        case .screenRuler: return "Счёт"
        case .sysMonitors: return "Система"
        case .diskSpace: return "Система"
        case .batteryInfo: return "Система"
        case .uptimeInfo: return "Система"
        case .publicIP: return "Система"
        case .pingHost: return "Система"
        case .speedTest: return "Система"
        case .folderSize: return "Система"
        case .bigFiles: return "Система"
        case .emptyTrash: return "Система"
        case .caffeinate: return "Система"
        case .themeToggle: return "Система"
        case .dndToggle: return "Система"
        case .killProcess: return "Система"
        case .wifiList: return "Система"
        case .shotArea: return "Медиа"
        case .shotWindow: return "Медиа"
        case .ocrShot: return "Медиа"
        case .micRecord: return "Медиа"
        case .voiceNotes: return "Медиа"
        case .imgConvertExt: return "Медиа"
        case .pdfCompress: return "Медиа"
        case .pdfMerge: return "Медиа"
        case .pdfSplit: return "Медиа"
        case .imgRotate: return "Медиа"
        case .imgWatermark: return "Медиа"
        case .videoDownload: return "Медиа"
        case .videoAudio: return "Медиа"
        case .videoGif: return "Медиа"
        case .videoCompress: return "Медиа"
        case .batchRename: return "Медиа"
        case .gitStatus: return "Код"
        case .gitLog: return "Код"
        case .todoCount: return "Код"
        case .openEditor: return "Код"
        case .localServer: return "Код"
        case .portWho: return "Код"
        case .ngrokTunnel: return "Код"
        case .sqlSelect: return "Код"
        case .sqlFormat: return "Код"
        case .cronExplain: return "Код"
        case .weatherNow: return "Инфо"
        case .ratesLive: return "Инфо"
        case .quickSticky: return "Инфо"
        case .shoppingList: return "Инфо"
        case .rssFeed: return "Инфо"
        case .hnFeed: return "Инфо"
        case .birthdaysNear: return "Инфо"
        case .tgSelf: return "Инфо"
        case .scratchpad: return "Инфо"
        case .sysSchedule: return "Инфо"
        case .pomodoro: return "Время"
        case .metronome: return "Время"
        case .stopwatch: return "Время"
        case .countdownDate: return "Время"
        case .worldClock: return "Время"
        case .backToTask: return "Время"
        case .stretchReminder: return "Время"
        case .waterCounter: return "Время"
        case .breathe: return "Время"
        case .quoteOfDay: return "Время"
        case .jokeOfDay: return "Время"
        case .game2048: return "Игры"
        case .snake: return "Игры"
        case .mines: return "Игры"
        case .tamagotchi: return "Игры"
        case .siteBlocker: return "Игры"
        case .pomodoroStats: return "Игры"
        case .hotkeyCheat: return "Игры"
        case .sizeConvert: return "Игры"
        case .tzConvert: return "Игры"
        case .pasteClean: return "Игры"
        case .dupFinder: return "Система"
        case .dnsWho: return "Система"
        case .remindLater: return "Время"
        case .imgShrink: return "Медиа"
        }
    }

    /// Реализованные на текущий момент тула (батч 1: текст, счёт, время).
    var implemented: Bool { ToolImplementations.contains(self) }
}

let ToolImplementations: Set<ToolID> = [
    .stripFormat, .charCount, .caseConvert, .translit, .base64,
    .urlEncode, .jsonFormat, .sha256, .uuidGen, .passGen,
    .unixTime, .regexTest, .textDiff, .loremIpsum, .morse,
    .romanNumerals, .calculator, .unitConvert, .currencyConvert, .percentCalc,
    .loanCalc, .randomPick, .randomFromList, .qrGen, .colorPicker,
    .hexRgb, .paletteImg, .screenRuler, .sysMonitors, .diskSpace,
    .batteryInfo, .uptimeInfo, .publicIP, .pingHost, .speedTest,
    .folderSize, .bigFiles, .emptyTrash, .caffeinate, .themeToggle,
    .dndToggle, .killProcess, .wifiList, .shotArea, .shotWindow,
    .ocrShot, .micRecord, .voiceNotes, .imgConvertExt, .pdfCompress,
    .pdfMerge, .pdfSplit, .imgRotate, .imgWatermark, .videoDownload,
    .videoAudio, .videoGif, .videoCompress, .batchRename, .gitStatus,
    .gitLog, .todoCount, .openEditor, .localServer, .portWho,
    .ngrokTunnel, .sqlSelect, .sqlFormat, .cronExplain, .weatherNow,
    .ratesLive, .quickSticky, .shoppingList, .rssFeed, .hnFeed,
    .birthdaysNear, .tgSelf, .scratchpad, .sysSchedule, .pomodoro,
    .metronome, .stopwatch, .countdownDate, .worldClock, .backToTask,
    .stretchReminder, .waterCounter, .breathe, .quoteOfDay, .jokeOfDay,
    .game2048, .snake, .mines, .tamagotchi, .siteBlocker,
    .pomodoroStats, .hotkeyCheat, .sizeConvert, .tzConvert, .pasteClean,
    .dupFinder, .dnsWho, .remindLater, .imgShrink,
]
struct ToolComingView: View {
    let tool: ToolID
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: tool.icon).font(.system(size: 34, weight: .light)).foregroundStyle(.secondary)
            Text(tool.title).font(.headline)
            Text(L("В работе - реализую по одной из реестра"))
                .font(.caption).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, minHeight: 160).padding()
    }
}
