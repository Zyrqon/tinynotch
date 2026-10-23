import SwiftUI
import AppKit
import CryptoKit
import ImageIO
import UserNotifications

// MARK: - 104 Дубликаты файлов

struct DupFinderTool: View {
    @ViewState private var scanning = false
    @ViewState private var result = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Button(scanning ? L("Ищу…") : L("Выбрать папку")) { pick() }
                    .buttonStyle(.bordered).controlSize(.small).disabled(scanning)
                if !result.isEmpty {
                    Button(L("Очистить")) { result = "" }.buttonStyle(.bordered).controlSize(.small)
                }
            }
            Text(result.isEmpty ? L("Ищу одинаковые файлы по хешу: сначала размер, потом содержимое") : result)
                .font(.system(size: 10, design: .monospaced))
                .frame(maxWidth: .infinity, minHeight: 120, alignment: .topLeading)
                .textSelection(.enabled)
        }
    }

    private func pick() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let folder = panel.url else { return }
        scanning = true
        result = L("Сканирую…")
        let root = folder
        DispatchQueue.global(qos: .userInitiated).async {
            var bySize: [Int: [URL]] = [:]
            let fm = FileManager.default
            let en = fm.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey])
            while let item = en?.nextObject() as? URL {
                guard let vals = try? item.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                      vals.isRegularFile == true, let size = vals.fileSize, size > 0 else { continue }
                bySize[size, default: []].append(item)
            }
            var groups: [(Int, [URL])] = []
            for (size, urls) in bySize where urls.count > 1 {
                var byHash: [String: [URL]] = [:]
                for url in urls {
                    guard let data = try? Data(contentsOf: url) else { continue }
                    let digest = Insecure.MD5.hash(data: data)
                    let hex = digest.map { String(format: "%02x", $0) }.joined()
                    byHash[hex, default: []].append(url)
                }
                for (_, same) in byHash where same.count > 1 { groups.append((size, same)) }
            }
            groups.sort { $0.0 * ($0.1.count - 1) > $1.0 * ($1.1.count - 1) }
            var lines: [String] = []
            var wasted = 0
            for (size, same) in groups.prefix(20) {
                wasted += size * (same.count - 1)
                let names = same.map { $0.lastPathComponent }.joined(separator: "  •  ")
                lines.append("\(same.count) шт × \(size / 1024) КБ: \(names)")
            }
            let head = groups.isEmpty ? L("Дубликатов нет") :
                L("Групп дубликатов: \(groups.count), лишний вес: \(wasted / 1024 / 1024) МБ")
            DispatchQueue.main.async {
                scanning = false
                result = (head + "\n" + lines.joined(separator: "\n")).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
    }
}

// MARK: - 105 Сеть: DNS и whois

struct DnsWhoTool: View {
    @ViewState private var host = "ya.ru"
    @ViewState private var output = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField(L("Хост"), text: $host).textFieldStyle(.roundedBorder)
            HStack(spacing: 6) {
                Button(L("DNS")) { run("dns") }.buttonStyle(.bordered).controlSize(.small)
                Button(L("Whois")) { run("whois") }.buttonStyle(.bordered).controlSize(.small)
                Button(L("Ping")) { run("ping") }.buttonStyle(.bordered).controlSize(.small)
            }
            Text(output.isEmpty ? "—" : output)
                .font(.system(size: 10, design: .monospaced))
                .frame(maxWidth: .infinity, minHeight: 90, alignment: .topLeading)
                .textSelection(.enabled)
        }
    }

    private func run(_ kind: String) {
        let safe = host.replacingOccurrences(of: ";", with: "")
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "&", with: "")
        output = L("Запрос…")
        DispatchQueue.global(qos: .userInitiated).async {
            var text = ""
            switch kind {
            case "dns":
                text = Shell.run("dig +short \(safe) A; dig +short \(safe) AAAA; dig +short \(safe) MX")
            case "whois":
                text = Shell.run("whois \(safe) 2>&1 | head -30")
            default:
                text = Shell.run("ping -c 3 \(safe) 2>&1 | tail -4")
            }
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            DispatchQueue.main.async { output = trimmed.isEmpty ? L("Пусто") : trimmed }
        }
    }
}

// MARK: - 106 Напомни через N

struct RemindLaterTool: View {
    @ViewState private var minutes = "10"
    @ViewState private var note = ""
    @ViewState private var status = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                TextField(L("Минут"), text: $minutes)
                    .textFieldStyle(.roundedBorder).frame(width: 70)
                TextField(L("О чём напомнить"), text: $note).textFieldStyle(.roundedBorder)
            }
            Button(L("Напомнить")) { schedule() }.buttonStyle(.bordered).controlSize(.small)
            if !status.isEmpty {
                Text(status).font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    private func schedule() {
        let mins = Double(minutes) ?? 0
        guard mins > 0 else { status = L("Нужны минуты больше нуля"); return }
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { ok, _ in
            DispatchQueue.main.async {
                guard ok else { status = L("Нет разрешения на уведомления"); return }
                let content = UNMutableNotificationContent()
                content.title = L("Напоминание")
                content.body = note.isEmpty ? L("Пора!") : note
                content.sound = .default
                let trigger = UNTimeIntervalNotificationTrigger(timeInterval: mins * 60, repeats: false)
                let req = UNNotificationRequest(identifier: "tiny-remind-\(Date().timeIntervalSince1970)", content: content, trigger: trigger)
                center.add(req) { err in
                    DispatchQueue.main.async {
                        status = err == nil ? L("Поставил: через \(Int(mins)) мин") : err!.localizedDescription
                    }
                }
            }
        }
    }
}

// MARK: - 107 Сжать картинки

struct ImgShrinkTool: View {
    @ViewState private var working = false
    @ViewState private var result = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(working ? L("Сжимаю…") : L("Выбрать картинки")) { pick() }
                .buttonStyle(.bordered).controlSize(.small).disabled(working)
            Text(result.isEmpty ? L("Копии до 1600px, JPEG 70%. Оригиналы не трогаю") : result)
                .font(.system(size: 10, design: .monospaced))
                .frame(maxWidth: .infinity, minHeight: 90, alignment: .topLeading)
                .textSelection(.enabled)
        }
    }

    private func pick() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK, !panel.urls.isEmpty else { return }
        working = true
        result = L("Сжимаю…")
        let urls = panel.urls
        DispatchQueue.global(qos: .userInitiated).async {
            let exts = ["jpg", "jpeg", "png", "heic", "tiff", "bmp", "webp"]
            var files: [URL] = []
            let fm = FileManager.default
            for url in urls {
                var isDir: ObjCBool = false
                if fm.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
                    if let en = fm.enumerator(at: url, includingPropertiesForKeys: nil) {
                        while let f = en.nextObject() as? URL {
                            if exts.contains(f.pathExtension.lowercased()) { files.append(f) }
                        }
                    }
                } else {
                    files.append(url)
                }
            }
            var lines: [String] = []
            for f in files.prefix(60) {
                guard let src = CGImageSourceCreateWithURL(f as CFURL, nil) else { continue }
                let opts: [CFString: Any] = [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceThumbnailMaxPixelSize: 1600,
                    kCGImageSourceCreateThumbnailWithTransform: true
                ]
                guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { continue }
                let rep = NSBitmapImageRep(cgImage: cg)
                guard let jpeg = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.7]) else { continue }
                let outURL = f.deletingPathExtension().appendingPathExtension("small.jpg")
                try? jpeg.write(to: outURL)
                let attrs = try? fm.attributesOfItem(atPath: f.path)
                let before = (attrs?[.size] as? Int) ?? 0
                lines.append("\(f.lastPathComponent): \(max(before / 1024, 1)) → \(max(jpeg.count / 1024, 1)) КБ")
            }
            let done = lines.count
            DispatchQueue.main.async {
                working = false
                result = done == 0 ? L("Картинок не нашлось") : L("Сжато: \(done)") + "\n" + lines.joined(separator: "\n")
            }
        }
    }
}

// MARK: - 108 AirDrop

struct AirDropTool: View {
    @ViewState private var status = ""
    @ViewState private var dropActive = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Button(L("Выбрать файлы")) { pick() }.buttonStyle(.bordered).controlSize(.small)
                Button(L("Буфер → файл")) { clipboardFile() }.buttonStyle(.bordered).controlSize(.small)
            }
            RoundedRectangle(cornerRadius: 8)
                .fill(dropActive ? Color.accentColor.opacity(0.15) : Color.primary.opacity(0.04))
                .frame(height: 70)
                .overlay(Text(L("Перетащи файлы сюда")).font(.caption).foregroundStyle(.secondary))
                .onDrop(of: [.fileURL], isTargeted: Binding(get: { dropActive }, set: { dropActive = $0 })) { providers in
                    var urls: [URL] = []
                    let group = DispatchGroup()
                    for provider in providers {
                        group.enter()
                        _ = provider.loadObject(ofClass: URL.self) { url, _ in
                            if let url { urls.append(url) }
                            group.leave()
                        }
                    }
                    group.notify(queue: .main) { if !urls.isEmpty { send(urls) } }
                    return true
                }
            if !status.isEmpty {
                Text(status).font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    private func pick() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK, !panel.urls.isEmpty else { return }
        send(panel.urls)
    }

    private func clipboardFile() {
        let pasteboard = NSPasteboard.general
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL], let url = urls.first {
            send([url])
        } else if let text = pasteboard.string(forType: .string), !text.isEmpty {
            let target = ToolOutput.uniqueURL(name: "airdrop.txt")
            try? text.write(to: target, atomically: true, encoding: .utf8)
            send([target])
        } else if let image = NSImage(pasteboard: pasteboard) {
            if let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
               let png = rep.representation(using: .png, properties: [:]) {
                let target = ToolOutput.uniqueURL(name: "airdrop.png")
                try? png.write(to: target)
                send([target])
            }
        } else {
            status = L("В буфере нет файла, текста или картинки")
        }
    }

    private func send(_ urls: [URL]) {
        guard let service = NSSharingService(named: .sendViaAirDrop), service.canPerform(withItems: urls) else {
            status = L("AirDrop недоступен")
            return
        }
        status = L("Открываю AirDrop: \(urls.count) файл(ов)")
        service.perform(withItems: urls)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { status = L("Окно AirDrop открыто, выбери получателя") }
    }
}
