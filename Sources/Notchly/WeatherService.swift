import CoreLocation
import Foundation

struct Weather: Equatable {
    var temperature: Int
    var high: Int
    var low: Int
    var code: Int
    var isDay: Bool
    var city: String?
    var latitude: Double
    var longitude: Double

    /// Страница с прогнозом на несколько дней вперёд.
    var forecastURL: URL {
        URL(string: String(format: "https://yandex.ru/pogoda/?lat=%.4f&lon=%.4f", latitude, longitude))!
    }

    var symbol: String {
        switch code {
        case 0: return isDay ? "sun.max.fill" : "moon.stars.fill"
        case 1, 2: return isDay ? "cloud.sun.fill" : "cloud.moon.fill"
        case 3: return "cloud.fill"
        case 45, 48: return "cloud.fog.fill"
        case 51...57: return "cloud.drizzle.fill"
        case 61...67, 80...82: return "cloud.rain.fill"
        case 71...77, 85, 86: return "cloud.snow.fill"
        case 95...99: return "cloud.bolt.rain.fill"
        default: return "cloud.fill"
        }
    }

    var summary: String {
        switch code {
        case 0: return L("Ясно")
        case 1: return L("Почти ясно")
        case 2: return L("С прояснениями")
        case 3: return L("Пасмурно")
        case 45, 48: return L("Туман")
        case 51...57: return L("Морось")
        case 61...67: return L("Дождь")
        case 71...77: return L("Снег")
        case 80...82: return L("Ливень")
        case 85, 86: return L("Снегопад")
        case 95...99: return L("Гроза")
        default: return L("Облачно")
        }
    }
}

/// Погода из Open-Meteo (без ключей). Место — из геолокации macOS,
/// а если доступ не выдан — примерно по IP.
final class WeatherService: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published private(set) var weather: Weather?

    /// Для снапшотов: вымышленная погода вместо настоящей геолокации.
    func debugSet(_ weather: Weather) {
        timer?.invalidate()
        frozen = true
        self.weather = weather
    }

    private let location = CLLocationManager()
    private var coordinate: CLLocationCoordinate2D?
    private var city: String?
    private var timer: Timer?
    private var lastFetch = Date.distantPast

    /// live = false — для снапшотов: ни сети, ни геолокации.
    init(live: Bool = true) {
        super.init()
        frozen = !live
        guard live else { return }
        location.delegate = self
        location.desiredAccuracy = kCLLocationAccuracyKilometer
        timer = Timer.scheduledTimer(withTimeInterval: 15 * 60, repeats: true) { [weak self] _ in
            self?.refresh(force: true)
        }
        start()
    }

    /// Снапшоты: погода вымышленная, никаких запросов в сеть и геолокации — иначе на скриншоты
    /// попал бы настоящий город.
    private var frozen = false

    func refresh(force: Bool = false) {
        guard !frozen else { return }
        guard force || Date().timeIntervalSince(lastFetch) > 10 * 60 else { return }
        if let coordinate { fetch(coordinate) } else { start() }
    }

    /// Точная геолокация: спрашиваем только по нажатию на карточку погоды.
    var canAskForPreciseLocation: Bool { location.authorizationStatus == .notDetermined }

    func askForPreciseLocation() {
        guard canAskForPreciseLocation else { return }
        location.requestWhenInUseAuthorization()
    }

    private func start() {
        guard !frozen else { return }
        switch location.authorizationStatus {
        case .authorizedAlways, .authorized:
            location.requestLocation()
        default:
            locateByIP()
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorized: manager.requestLocation()
        case .denied, .restricted: locateByIP()
        default: break
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        coordinate = loc.coordinate
        CLGeocoder().reverseGeocodeLocation(loc, preferredLocale: Loc.locale) { [weak self] marks, _ in
            self?.city = marks?.first?.locality
            self?.fetch(loc.coordinate)
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        if coordinate == nil { locateByIP() }
    }

    /// open-meteo и ipapi.co отсюда недоступны: опираемся на wttr.in — он и город по IP
    /// определяет, и погоду отдаёт. Если геолокация известна, запрашиваем её точно.
    private func locateByIP() {
        fetch(nil)
    }

    private func fetch(_ c: CLLocationCoordinate2D?) {
        lastFetch = Date()
        let locPart = c.map { "~\(String(format: "%.2f", $0.latitude)),\(String(format: "%.2f", $0.longitude))" } ?? ""
        let url = URL(string: "https://wttr.in/\(locPart)?format=j1")!
        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let data, let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let current = (json["current_condition"] as? [[String: Any]])?.first,
                  let tempString = current["temp_C"] as? String, let temp = Double(tempString) else { return }
            let daily = (json["weather"] as? [[String: Any]])?.first
            let high = Double(daily?["maxtempC"] as? String ?? "") ?? temp
            let low = Double(daily?["mintempC"] as? String ?? "") ?? temp
            let area = ((json["nearest_area"] as? [[String: Any]])?.first?["areaName"] as? [[String: Any]])?.first?["value"] as? String
            DispatchQueue.main.async {
                guard let self else { return }
                guard !self.frozen else { return }
                if self.city == nil { self.city = area }
                self.weather = Weather(temperature: Int(temp.rounded()), high: Int(high.rounded()),
                                       low: Int(low.rounded()), code: Int(current["weatherCode"] as? String ?? "") ?? 3,
                                       isDay: (current["isday"] as? String ?? "1") == "1",
                                       city: self.city,
                                       latitude: c?.latitude ?? 0, longitude: c?.longitude ?? 0)
            }
        }.resume()
    }
}
