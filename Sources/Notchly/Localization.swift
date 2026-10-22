import Foundation

/// Язык интерфейса. Меняется в настройках на лету, без перезапуска.
enum AppLanguage: String, CaseIterable, Codable, Identifiable {
    case ru, en
    var id: String { rawValue }
    /// Название языка на нём самом — так его узнают в любом случае.
    var title: String { self == .ru ? "Русский" : "English" }

    /// По умолчанию — как в системе: русский для русской macOS, иначе английский.
    static var system: AppLanguage {
        (Locale.preferredLanguages.first ?? "en").hasPrefix("ru") ? .ru : .en
    }
}

enum Loc {
    static var language: AppLanguage = .ru
    static var isRussian: Bool { language == .ru }
    /// Локаль для дат и чисел.
    static var locale: Locale { Locale(identifier: isRussian ? "ru_RU" : "en_US") }

    /// Русский или английский вариант — для склонений и фраз, которые проще написать целиком.
    static func pick(_ ru: String, _ en: String) -> String { isRussian ? ru : en }

    /// «1 задача / 2 задачи / 5 задач» и «1 task / 5 tasks».
    static func plural(_ n: Int, _ one: String, _ few: String, _ many: String, en: String, enPlural: String) -> String {
        guard isRussian else { return n == 1 ? en : enPlural }
        let mod10 = n % 10, mod100 = n % 100
        if mod10 == 1 && mod100 != 11 { return one }
        if (2...4).contains(mod10) && !(12...14).contains(mod100) { return few }
        return many
    }
}

/// Строка интерфейса. Исходник — русский текст, он же ключ английского словаря (`English.table`).
func L(_ ru: String) -> String {
    Loc.isRussian ? ru : (English.table[ru] ?? ru)
}

/// Строка с подстановками: ключ — русский текст с `%@` на месте значений.
func L(_ ru: String, _ args: CVarArg...) -> String {
    String(format: L(ru), locale: Loc.locale, arguments: args)
}
