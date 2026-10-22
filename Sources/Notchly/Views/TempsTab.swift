import SwiftUI

/// Вкладка «Система»: монитор нагрузок в стиле htop и температуры всех датчиков.
struct SystemTab: View {
    @ObservedObject var sys: SysMonitor
    @ViewState private var mode = 0              // 0 - монитор, 1 - температуры
    @ViewState private var hoverKey: String? = nil

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    ForEach(0..<2, id: \.self) { i in
                        Button { mode = i } label: {
                            Text(L(i == 0 ? "Монитор" : "Температуры"))
                                .font(.system(size: 11.5, weight: .semibold))
                                .foregroundStyle(mode == i ? Color.black : Color.white.opacity(0.6))
                                .padding(.horizontal, 11)
                                .frame(height: 24)
                                .background(Capsule().fill(mode == i ? Color.white : Color.white.opacity(0.08)))
                                .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                if mode == 0 { monitorView(sys.sample) } else { tempsView(sys.sample) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 22)
            .padding(.vertical, 12)
        }
    }

    // MARK: - Монитор

    private func monitorView(_ s: SysSample) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if s.cores.isEmpty {
                Text(L("Нет данных: проверь tools/notchly-temps"))
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .padding(.top, 20)
            } else {
                HStack(alignment: .top, spacing: 16) {
                    VStack(spacing: 6) {
                        ForEach(0..<min(4, s.cores.count), id: \.self) { i in
                            barRow("E\(i + 1)", Double(s.cores[i]) / 100, "\(s.cores[i])%")
                        }
                    }
                    VStack(spacing: 6) {
                        ForEach(4..<min(8, s.cores.count), id: \.self) { i in
                            barRow("P\(i - 3)", Double(s.cores[i]) / 100, "\(s.cores[i])%")
                        }
                    }
                }
                barRow(L("Память"), s.memTotal > 0 ? s.memUsed / s.memTotal : 0,
                       String(format: "%.1f ГБ", s.memUsed / 1024))
                barRow(L("Своп"), s.swapTotal > 0 ? s.swapUsed / s.swapTotal : 0,
                       String(format: "%.1f ГБ", s.swapUsed / 1024))
                Text(Loc.pick(
                    "Задач \(s.tasks) · потоков \(s.threads) · нагрузка \(loadText(s.load)) · аптайм \(uptimeText(s.uptime))",
                    "Tasks \(s.tasks) · threads \(s.threads) · load \(loadText(s.load)) · uptime \(uptimeText(s.uptime))"))
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func barRow(_ name: String, _ frac: Double, _ label: String) -> some View {
        HStack(spacing: 8) {
            Text(name)
                .font(.system(size: 11, weight: .medium))
                .frame(width: 52, alignment: .leading)
                .foregroundStyle(.secondary)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.10))
                    Capsule().fill(barColor(frac))
                        .frame(width: max(4, geo.size.width * min(1, max(0, frac))))
                }
            }
            .frame(height: 8)
            Text(label)
                .font(.system(size: 11, design: .rounded))
                .monospacedDigit()
                .frame(width: 56, alignment: .trailing)
        }
    }

    private func barColor(_ frac: Double) -> Color {
        frac >= 0.9 ? .red : (frac >= 0.85 ? .orange : (frac >= 0.6 ? .orange : .green))
    }

    private func loadText(_ load: [Double]) -> String {
        load.prefix(3).map { String(format: "%.1f", $0) }.joined(separator: " ")
    }

    private func uptimeText(_ t: TimeInterval) -> String {
        let d = Int(t) / 86400, h = (Int(t) % 86400) / 3600
        return d > 0 ? "\(d) д \(h) ч" : "\(h) ч"
    }

    // MARK: - Температуры

    private func tempsView(_ s: SysSample) -> some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 10) {
                let groups = tempGroups(s)
                // Два столбика: слева процессор, справа графика и батарея.
                HStack(alignment: .top, spacing: 16) {
                    if groups.count > 0 { groupBlock(groups[0], "cpu") }
                    VStack(alignment: .leading, spacing: 8) {
                        if groups.count > 1 { groupBlock(groups[1], "gpu") }
                        if groups.count > 2 { groupBlock(groups[2], "batt") }
                    }
                }
                // Прочее: тоже в два столбика.
                if groups.count > 3 {
                    groupBlock(groups[3], "misc", columns: true)
                }
            }
            .padding(.bottom, 4)
        }
    }

    private func groupBlock(_ g: (String, [(String, Double)]), _ prefix: String, columns: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(g.0)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(.secondary)
            if columns {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible())], spacing: 1) {
                    ForEach(g.1.indices, id: \.self) { i in
                        tempRow(g.1[i].0, g.1[i].1, "\(prefix)-\(i)")
                    }
                }
            } else {
                ForEach(g.1.indices, id: \.self) { i in
                    tempRow(g.1[i].0, g.1[i].1, "\(prefix)-\(i)")
                }
            }
        }
    }

    private func tempRow(_ name: String, _ v: Double, _ key: String) -> some View {
        HStack {
            Text(name).font(.system(size: 11.5)).lineLimit(1)
            Spacer(minLength: 6)
            Text("\(Int(v.rounded()))°C")
                .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(heatColor(v))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: 7).fill(Color.white.opacity(hoverKey == key ? 0.12 : 0)))
        .contentShape(Rectangle())
        .onHover { inside in
            hoverKey = inside ? key : (hoverKey == key ? nil : hoverKey)
        }
    }

    private func heatColor(_ v: Double) -> Color {
        v >= 90 ? .red : (v >= 75 ? .orange : .green)
    }

    private func tempGroups(_ s: SysSample) -> [(String, [(String, Double)])] {
        var cpu: [(String, Double)] = []
        for (i, v) in s.ecore.enumerated() { cpu.append(("E-ядро \(i + 1)", v)) }
        for (i, v) in s.pcore.enumerated() { cpu.append(("P-ядро \(i + 1)", v)) }
        if s.pkg > 0 { cpu.append(("Пакет", s.pkg)) }
        var gpu: [(String, Double)] = []
        for (i, v) in s.gpu.enumerated() { gpu.append(("GPU Cluster \(i + 1)", v)) }
        let battNames = ["Ячейка 1", "Ячейка 2", "Ячейка 3", "Ячейка 4"]
        var batt: [(String, Double)] = []
        for (i, v) in s.batt.enumerated() { batt.append((i < battNames.count ? battNames[i] : "Ячейка", v)) }
        var misc: [(String, Double)] = [("Блок питания", s.psu), ("Зарядка", s.charger)]
        for (i, v) in s.trackpad.enumerated() { misc.append(("Трекпад \(i + 1)", v)) }
        misc.append(("Wi-Fi", s.wifi))
        misc.append(("SSD", s.ssd))
        misc.append(("Thunderbolt", s.tb))
        return [("Процессор", cpu), ("Графика", gpu), ("Батарея", batt), ("Прочее", misc)]
    }
}

// MARK: - Монитор системы

final class SysMonitor: ObservableObject {
    @Published private(set) var sample = SysSample()
    private var timer: Timer?
    private let queue = DispatchQueue(label: "notchly.sys", qos: .utility)

    init() {
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            self?.poll()
        }
        poll()
    }

    private func poll() {
        queue.async { [weak self] in
            let s = Self.fetch()
            DispatchQueue.main.async { self?.sample = s }
        }
    }

    private static func fetch() -> SysSample {
        let path = NSHomeDirectory() + "/Downloads/Notchly/tools/notchly-temps"
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return SysSample() }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        guard let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return SysSample()
        }
        var s = SysSample()
        s.ecore = obj["ecore"] as? [Double] ?? []
        s.pcore = obj["pcore"] as? [Double] ?? []
        s.pkg = obj["pkg"] as? Double ?? 0
        s.gpu = obj["gpu"] as? [Double] ?? []
        s.batt = obj["batt"] as? [Double] ?? []
        s.trackpad = obj["trackpad"] as? [Double] ?? []
        s.charger = obj["charger"] as? Double ?? 0
        s.psu = obj["psu"] as? Double ?? 0
        s.tb = obj["tb"] as? Double ?? 0
        s.wifi = obj["wifi"] as? Double ?? 0
        s.ssd = obj["ssd"] as? Double ?? 0
        s.cores = obj["cores"] as? [Int] ?? []
        if let m = obj["mem"] as? [String: Any] {
            s.memUsed = m["used"] as? Double ?? 0
            s.memTotal = m["total"] as? Double ?? 0
        }
        if let m = obj["swap"] as? [String: Any] {
            s.swapUsed = m["used"] as? Double ?? 0
            s.swapTotal = m["total"] as? Double ?? 0
        }
        s.load = obj["load"] as? [Double] ?? []
        s.tasks = obj["tasks"] as? Int ?? 0
        s.threads = obj["threads"] as? Int ?? 0
        s.uptime = obj["uptime"] as? Double ?? 0
        return s
    }
}

struct SysSample {
    var ecore: [Double] = []
    var pcore: [Double] = []
    var pkg: Double = 0
    var gpu: [Double] = []
    var batt: [Double] = []
    var trackpad: [Double] = []
    var charger: Double = 0
    var psu: Double = 0
    var tb: Double = 0
    var wifi: Double = 0
    var ssd: Double = 0
    var cores: [Int] = []
    var memUsed: Double = 0
    var memTotal: Double = 0
    var swapUsed: Double = 0
    var swapTotal: Double = 0
    var load: [Double] = []
    var tasks: Int = 0
    var threads: Int = 0
    var uptime: Double = 0
}
