import AppKit
import LocalAuthentication
import SwiftUI

struct APIKey: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    var value: String
    var createdAt = Date()

    /// «sk-proj…4f2a» — начало и конец ключа, середина скрыта.
    var masked: String {
        guard value.count > 10 else { return String(repeating: "•", count: max(value.count, 6)) }
        return "\(value.prefix(6))••••\(value.suffix(4))"
    }
}

/// API-ключи в Связке ключей. Открываются только через Touch ID или пароль Mac
/// и сами закрываются, когда остров сворачивается или через 2 минуты.
final class KeyVault: ObservableObject {
    @Published private(set) var isUnlocked = false
    @Published private(set) var keys: [APIKey] = []
    @Published private(set) var authError: String?

    private var lockWork: DispatchWorkItem?
    private static let account = "vault"

    func unlock() {
        guard !isUnlocked else { return }
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            authError = L("На этом Mac недоступны Touch ID и пароль")
            return
        }
        // Окно Touch ID должно оказаться поверх всего и принимать ввод пароля.
        NSApp.activate(ignoringOtherApps: true)
        context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: L("открыть API-ключи")) { [weak self] ok, _ in
            DispatchQueue.main.async {
                guard let self else { return }
                if ok {
                    self.keys = self.load()
                    self.authError = nil
                    withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) { self.isUnlocked = true }
                    self.scheduleLock()
                } else {
                    self.authError = L("Не удалось подтвердить личность")
                }
            }
        }
    }

    func lock() {
        lockWork?.cancel()
        guard isUnlocked else { return }
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
            isUnlocked = false
            keys = []
        }
    }

    func add(name: String, value: String) {
        guard isUnlocked else { return }
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            keys.insert(APIKey(name: name.isEmpty ? L("Ключ %@", "\(keys.count + 1)") : name, value: value), at: 0)
        }
        save()
        scheduleLock()
    }

    func delete(_ key: APIKey) {
        guard isUnlocked else { return }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { keys.removeAll { $0.id == key.id } }
        save()
        scheduleLock()
    }

    /// Копирует ключ с пометкой «скрытое», чтобы его не записала история буфера обмена.
    func copy(_ key: APIKey) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.declareTypes([.string, NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")], owner: nil)
        pb.setString(key.value, forType: .string)
        pb.setString("", forType: NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType"))
        scheduleLock()
    }

    private func scheduleLock() {
        lockWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.lock() }
        lockWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 120, execute: work)
    }

    private func load() -> [APIKey] {
        guard let data = Keychain.data(service: "apikeys", account: Self.account) else { return [] }
        return (try? JSONDecoder().decode([APIKey].self, from: data)) ?? []
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(keys) else { return }
        Keychain.set(data, service: "apikeys", account: Self.account)
    }
}
