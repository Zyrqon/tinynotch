import AppKit

/// Запасной источник для Apple Music и Spotify через AppleScript.
/// Опрашивает только уже запущенные приложения, чтобы случайно их не открыть.
final class ScriptablePlayers {
    enum Player: CaseIterable {
        case music, spotify

        var bundleID: String {
            switch self {
            case .music: return "com.apple.Music"
            case .spotify: return "com.spotify.client"
            }
        }
    }

    enum Command {
        case playPause, next, previous, seek(Double)
    }

    struct Snapshot {
        var player: Player
        var title: String
        var artist: String
        var album: String
        var duration: Double
        var position: Double
        var playing: Bool
    }

    func poll() -> Snapshot? {
        let snapshots = Player.allCases.filter(isRunning).compactMap(snapshot(of:))
        return snapshots.first(where: \.playing) ?? snapshots.first
    }

    func perform(_ command: Command, on player: Player) {
        guard isRunning(player) else { return }
        let verb: String
        switch command {
        case .playPause: verb = "playpause"
        case .next: verb = "next track"
        case .previous: verb = "previous track"
        case .seek(let t): verb = "set player position to \(String(format: "%.2f", t))"
        }
        run("tell application id \"\(player.bundleID)\" to \(verb)")
    }

    func loadArtwork(for player: Player, completion: @escaping (NSImage?) -> Void) {
        switch player {
        case .music:
            let desc = run("tell application id \"com.apple.Music\" to get raw data of artwork 1 of current track")
            completion(desc.flatMap { NSImage(data: $0.data) })
        case .spotify:
            guard let urlString = run("tell application id \"com.spotify.client\" to get artwork url of current track")?.stringValue,
                  let url = URL(string: urlString) else { return completion(nil) }
            URLSession.shared.dataTask(with: url) { data, _, _ in
                let image = data.flatMap(NSImage.init(data:))
                DispatchQueue.main.async { completion(image) }
            }.resume()
        }
    }

    private func isRunning(_ player: Player) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: player.bundleID).isEmpty
    }

    private func snapshot(of player: Player) -> Snapshot? {
        let source = """
        tell application id "\(player.bundleID)"
            set ps to (player state as text)
            if ps is "stopped" then return {ps}
            set t to current track
            return {ps, name of t, artist of t, album of t, duration of t, player position}
        end tell
        """
        guard let list = run(source), list.numberOfItems >= 6 else { return nil }
        let state = list.atIndex(1)?.stringValue ?? ""
        var duration = list.atIndex(5)?.doubleValue ?? 0
        if player == .spotify { duration /= 1000 } // Spotify отдаёт миллисекунды
        let title = list.atIndex(2)?.stringValue ?? ""
        guard !title.isEmpty else { return nil }
        return Snapshot(player: player,
                        title: title,
                        artist: list.atIndex(3)?.stringValue ?? "",
                        album: list.atIndex(4)?.stringValue ?? "",
                        duration: duration,
                        position: list.atIndex(6)?.doubleValue ?? 0,
                        playing: state == "playing" || state == "kPSP")
    }

    @discardableResult
    private func run(_ source: String) -> NSAppleEventDescriptor? {
        var error: NSDictionary?
        let result = NSAppleScript(source: source)?.executeAndReturnError(&error)
        return error == nil ? result : nil
    }
}
