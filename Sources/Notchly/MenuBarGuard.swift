import AppKit
import ApplicationServices

/// Не даёт курсору коснуться верхней кромки экрана над островом, чтобы не выезжала строка меню
/// (при автоскрытии и в полноэкранных приложениях). Работает на уровне событий мыши,
/// ещё до того, как их увидит система, — нужен тот же доступ «Универсальный доступ».
final class MenuBarGuard {
    /// Зона над островом в координатах CoreGraphics: диапазон X и Y верхней кромки экрана.
    var zone: (() -> (xRange: ClosedRange<CGFloat>, top: CGFloat)?)?
    private(set) var isActive = false

    private var tap: CFMachPort?
    private var retryTimer: Timer?
    private static let margin: CGFloat = 4

    func start() {
        if AXIsProcessTrusted() { return install() }
        retryTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] timer in
            guard AXIsProcessTrusted() else { return }
            timer.invalidate()
            self?.install()
        }
    }

    private func install() {
        let mask = CGEventMask(1 << CGEventType.mouseMoved.rawValue)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cghidEventTap, place: .headInsertEventTap, options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, refcon in
                guard let refcon else { return Unmanaged.passUnretained(event) }
                return Unmanaged<MenuBarGuard>.fromOpaque(refcon).takeUnretainedValue().handle(type, event)
            },
            userInfo: refcon)
        else { return }
        self.tap = tap
        CFRunLoopAddSource(CFRunLoopGetMain(), CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0), .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        isActive = true
    }

    private func handle(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        guard let zone = zone?() else { return Unmanaged.passUnretained(event) }
        var point = event.location
        let limit = zone.top + Self.margin
        if zone.xRange.contains(point.x), point.y < limit, point.y >= zone.top - 1 {
            point.y = limit
            event.location = point
            CGWarpMouseCursorPosition(point)
        }
        return Unmanaged.passUnretained(event)
    }
}
