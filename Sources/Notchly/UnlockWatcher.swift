import Foundation

/// Следит за разблокировкой Mac: после входа в систему запускает приветственную анимацию острова.
final class UnlockWatcher {
    static let shared = UnlockWatcher()
    var onUnlock: (() -> Void)?

    private init() {
        DistributedNotificationCenter.default.addObserver(
            self,
            selector: #selector(unlocked),
            name: NSNotification.Name("com.apple.screenIsUnlocked"),
            object: nil
        )
    }

    @objc private func unlocked(_ note: Notification?) {
        DispatchQueue.main.async { [weak self] in self?.onUnlock?() }
    }
}
