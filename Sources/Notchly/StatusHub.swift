import Foundation
import Network

/// Статус печати с принтера. Пока поддержан Bambu Lab (MQTT на самом принтере).
struct PrinterStatus: Codable, Equatable {
    var state: String = "idle"      // idle / printing / paused / finished
    var percent: Int = 0
    var remaining: Int = 0          // секунд до конца
    var layer: Int = 0
    var layers: Int = 0
    var nozzle: Int = 0             // °C сопла
    var bed: Int = 0                // °C стола
    var name: String = ""           // имя задачи/файла

    var isPrinting: Bool { state == "printing" || state == "paused" }

    enum Keys: String, CodingKey {
        case state, percent, remaining, layer, layers, nozzle, bed, name
    }

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        state = try c.decodeIfPresent(String.self, forKey: .state) ?? "idle"
        percent = try c.decodeIfPresent(Int.self, forKey: .percent) ?? 0
        remaining = try c.decodeIfPresent(Int.self, forKey: .remaining) ?? 0
        layer = try c.decodeIfPresent(Int.self, forKey: .layer) ?? 0
        layers = try c.decodeIfPresent(Int.self, forKey: .layers) ?? 0
        nozzle = try c.decodeIfPresent(Int.self, forKey: .nozzle) ?? 0
        bed = try c.decodeIfPresent(Int.self, forKey: .bed) ?? 0
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
    }
}

/// Мини-HTTP-сервер на 127.0.0.1:8776. Сюда присылают статусы плагины агентов (opencode)
/// и внешний мост принтера. Всё локально, наружу не слушает.
final class StatusHub {
    private weak var model: IslandModel?
    private var listener: NWListener?
    private var restartWork: DispatchWorkItem?

    init(model: IslandModel) { self.model = model }

    func start() {
        restartWork?.cancel()
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        guard let listener = try? NWListener(using: params, on: 8776) else {
            DeviceBatteryMonitor.btlog("status-hub: порт 8776 занят")
            return
        }
        self.listener = listener
        listener.newConnectionHandler = { [weak self] conn in self?.accept(conn) }
        listener.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready: DeviceBatteryMonitor.btlog("status-hub: слушаю 8776")
            case .failed, .cancelled:
                let work = DispatchWorkItem { [weak self] in self?.start() }
                self.restartWork = work
                DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: work)
            default: break
            }
        }
        listener.start(queue: .main)
    }

    func stop() {
        restartWork?.cancel()
        listener?.cancel()
        listener = nil
    }

    private func accept(_ conn: NWConnection) {
        conn.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready: self?.read(conn)
            case .failed, .cancelled: conn.cancel()
            default: break
            }
        }
        conn.start(queue: .main)
    }

    private func read(_ conn: NWConnection) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, _ in
            guard let self else { return conn.cancel() }
            if let data { self.handle(conn, data: data) }
            if isComplete { conn.cancel() } else { self.read(conn) }
        }
    }

    private func handle(_ conn: NWConnection, data: Data) {
        guard let text = String(data: data, encoding: .utf8) else { return respond(conn, status: "400") }
        guard text.hasPrefix("POST ") else { return respond(conn, status: "404") }
        guard let headerEnd = text.range(of: "\r\n\r\n"),
              let line = text.split(separator: "\r\n").first,
              let path = line.split(separator: " ").dropFirst().first.map(String.init) else {
            return respond(conn, status: "400")
        }
        let body = String(text[headerEnd.upperBound...])
        let payload = body.data(using: .utf8) ?? Data()
        DispatchQueue.main.async {
            switch path {
            case "/agent": self.model?.pushAgent(payload: payload)
            case "/printer": self.model?.pushPrinter(payload: payload)
            default: break
            }
            self.respond(conn, status: "200")
        }
    }

    private func respond(_ conn: NWConnection, status: String) {
        let reply = "HTTP/1.1 \(status)\r\nContent-Length: 2\r\nConnection: close\r\n\r\nok"
        conn.send(content: reply.data(using: .utf8), completion: .contentProcessed { _ in conn.cancel() })
    }
}
