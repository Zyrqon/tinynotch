import Foundation
import Network
import Security

/// MQTT-клиент для Bambu Lab. Принтер сам раздаёт MQTT по TLS на порту 8883
/// (логин bblp, пароль — код доступа LAN). Подписываемся на device/+/report,
/// так что серийник знать не нужно.
final class BambuMonitor {
    var onStatus: ((PrinterStatus) -> Void)?
    var reader: (() -> (enabled: Bool, ip: String, code: String))?

    private var conn: NWConnection?
    private var buffer = Data()
    private var settingsKey = ""
    private var pingTimer: Timer?
    private var retryWork: DispatchWorkItem?
    private var pollTimer: Timer?

    func start() {
        let t = Timer(timeInterval: 10, repeats: true) { [weak self] _ in self?.sync() }
        RunLoop.main.add(t, forMode: .default)
        sync()
    }

    private func current() -> (enabled: Bool, ip: String, code: String)? {
        guard let reader else { return nil }
        let v = reader()
        guard v.enabled, !v.ip.isEmpty, !v.code.isEmpty else { return nil }
        return v
    }

    /// Раз в 10 секунд сверяем настройки: поменяли IP или код — переподключаемся.
    private func sync() {
        guard let v = current() else { tearDown(); return }
        let key = "\(v.ip)|\(v.code)"
        guard key != settingsKey else { return }
        settingsKey = key
        connect(ip: v.ip, code: v.code)
    }

    private func tearDown() {
        settingsKey = ""
        retryWork?.cancel()
        pingTimer?.invalidate()
        pingTimer = nil
        conn?.cancel()
        conn = nil
        buffer.removeAll()
    }

    private func connect(ip: String, code: String) {
        retryWork?.cancel()
        pingTimer?.invalidate()
        pingTimer = nil
        conn?.cancel()
        buffer.removeAll()
        // Самоподписанный сертификат принтера: проверку отключаем.
        let tls = NWProtocolTLS.Options()
        sec_protocol_options_set_verify_block(tls.securityProtocolOptions, { _, _, complete in complete(true) }, DispatchQueue.main)
        let params = NWParameters(tls: tls)
        params.allowLocalEndpointReuse = true
        let conn = NWConnection(host: NWEndpoint.Host(ip), port: 8883, using: params)
        self.conn = conn
        conn.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready: self?.handshake(code: code)
            case .failed, .cancelled: self?.scheduleRetry()
            default: break
            }
        }
        conn.start(queue: .main)
    }

    private func scheduleRetry() {
        conn = nil
        guard current() != nil, !settingsKey.isEmpty else { return }
        retryWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, let v = self.current() else { return }
            self.settingsKey = ""
            self.connect(ip: v.ip, code: v.code)
        }
        retryWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 15, execute: work)
    }

    // MARK: MQTT

    private func appendStr(_ s: String, to data: inout Data) {
        let bytes = Array(s.utf8)
        data.append(UInt8(bytes.count >> 8))
        data.append(UInt8(bytes.count & 0xFF))
        data.append(contentsOf: bytes)
    }

    private func send(packet: UInt8, payload: Data) {
        var rem = payload.count
        var lenBytes = Data()
        repeat {
            var byte = UInt8(rem % 128)
            rem /= 128
            if rem > 0 { byte |= 0x80 }
            lenBytes.append(byte)
        } while rem > 0
        var frame = Data([packet]) + lenBytes + payload
        guard let conn else { return }
        conn.send(content: frame, completion: .contentProcessed { _ in })
    }

    private func handshake(code: String) {
        var payload = Data()
        appendStr("MQTT", to: &payload)
        payload.append(0x04)                       // уровень протокола
        payload.append(0xC2)                       // clean session + логин + пароль
        payload.append(contentsOf: [0x00, 0x3C])   // keepalive 60 c
        appendStr("notchly", to: &payload)         // client id
        appendStr("bblp", to: &payload)
        appendStr(code, to: &payload)
        send(packet: 0x10, payload: payload)
    }

    private func subscribe() {
        var payload = Data([0x00, 0x01])           // packet id
        appendStr("device/+/report", to: &payload)
        payload.append(0x00)                       // qos 0
        send(packet: 0x82, payload: payload)
        pingTimer?.invalidate()
        let t = Timer(timeInterval: 25, repeats: true) { [weak self] _ in
            self?.send(packet: 0xC0, payload: Data())
        }
        RunLoop.main.add(t, forMode: .default)
        pingTimer = t
        DeviceBatteryMonitor.btlog("bambu: подписан")
    }

    private func receive() {
        guard let conn else { return }
        conn.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, _ in
            guard let self else { return }
            if let data {
                self.buffer.append(data)
                self.parsePackets()
            }
            if isComplete { self.scheduleRetry() } else { self.receive() }
        }
    }

    private func parsePackets() {
        while buffer.count >= 2 {
            let type = buffer[buffer.startIndex] & 0xF0
            var len = 0
            var mult = 1
            var idx = buffer.index(after: buffer.startIndex)
            var ok = false
            for _ in 0..<4 {
                guard idx < buffer.endIndex else { break }
                let byte = buffer[idx]
                len += Int(byte & 0x7F) * mult
                mult *= 128
                idx = buffer.index(after: idx)
                if byte & 0x80 == 0 { ok = true; break }
            }
            guard ok, idx < buffer.endIndex || len == 0 else { return }
            let total = buffer.distance(from: buffer.startIndex, to: idx) + len
            guard buffer.count >= total else { return }
            let body = buffer[idx ..< buffer.index(buffer.startIndex, offsetBy: total)]
            if type == 0x20 { subscribe() }
            else if type == 0x30 { handlePublish(Data(body)) }
            buffer.removeFirst(total)
        }
    }

    private func handlePublish(_ body: Data) {
        guard body.count > 2 else { return }
        let topicLen = Int(body[body.startIndex]) << 8 | Int(body[body.index(after: body.startIndex)])
        guard body.count >= 2 + topicLen else { return }
        let payload = body.suffix(from: body.index(body.startIndex, offsetBy: 2 + topicLen))
        guard let brace = payload.firstIndex(of: UInt8(ascii: "{")) else { return }
        guard let obj = (try? JSONSerialization.jsonObject(with: Data(payload[brace...]))) as? [String: Any],
              let pr = obj["print"] as? [String: Any] else { return }

        func num(_ key: String) -> Int? {
            if let i = pr[key] as? Int { return i }
            if let d = pr[key] as? Double { return Int(d) }
            if let s = pr[key] as? String { return Int(s.replacingOccurrences(of: " ", with: "")) }
            return nil
        }

        let raw = pr["gcode_state"] as? String ?? ""
        let state: String
        switch raw {
        case "RUNNING", "SLICING", "PREPARE": state = "printing"
        case "PAUSE": state = "paused"
        case "FINISHED": state = "finished"
        case "FAILED": state = "finished"
        default: state = "idle"
        }
        var st = PrinterStatus()
        st.state = state
        st.percent = min(100, max(0, num("print_pct") ?? num("mc_print_percent") ?? 0))
        st.remaining = num("remaining_time") ?? 0
        st.layer = num("layer_no") ?? 0
        st.layers = num("total_layers") ?? 0
        st.nozzle = num("nozzle_temper") ?? 0
        st.bed = num("bed_temper") ?? 0
        st.name = (pr["subtask_name"] as? String) ?? (pr["gcode_file"] as? String) ?? ""
        DispatchQueue.main.async { [weak self] in self?.onStatus?(st) }
    }
}
