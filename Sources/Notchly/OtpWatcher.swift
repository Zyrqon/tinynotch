import AppKit

/// Ловушка одноразовых кодов: новое текстовое содержимое буфера обмена
/// разбирается на коды и выносится карточкой с кнопкой «Скопировать».
final class OtpWatcher {
    var onCode: ((String) -> Void)?
    private var changeCount: Int
    private var timer: Timer?
    private var lastCode: String?

    init() {
        changeCount = NSPasteboard.general.changeCount
    }

    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.8, repeats: true) { [weak self] _ in
            self?.poll()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func poll() {
        let pb = NSPasteboard.general
        guard pb.changeCount != changeCount else { return }
        changeCount = pb.changeCount
        guard pb.canReadObject(forClasses: [NSString.self]) else { return }
        guard let text = pb.string(forType: .string), text.count <= 600 else { return }
        guard let code = Self.extractCode(from: text), code != lastCode else { return }
        lastCode = code
        onCode?(code)
    }

    /// Код: 4–8 цифр рядом со словом «код/code/verification…», либо отдельно
    /// стоящее число 4–6 цифр в коротком тексте (скопировали только код).
    /// Годы (19xx/20xx) и длинные последовательности не считаются кодами.
    static func extractCode(from text: String) -> String? {
        let keyword = "(?i)(?:код|код |code|verification|verify|подтвержд|одноразов|one[- ]time|otp|смс|sms)[^0-9]{0,24}([0-9]{4,8})(?:[^0-9]|$)"
        if let m = firstMatch(keyword, in: text) { return m }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count <= 24 else { return nil }
        guard let m = firstMatch("(?:^|[^0-9])([0-9]{4,6})(?:[^0-9]|$)", in: trimmed) else { return nil }
        if m.count == 4 && (m.hasPrefix("19") || m.hasPrefix("20")) { return nil }
        return m
    }

    private static func firstMatch(_ pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range), match.numberOfRanges > 1,
              let r = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[r])
    }
}
