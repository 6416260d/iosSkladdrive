import CoreLocation
import UIKit
import WebKit

/// Геопозиция курьера на карту «Нагрузки», и с погасшим экраном (UIBackgroundModes location, синий значок вверху):
/// POST /api/courier/geo {src: "ios"} не чаще раза в 30 с (сервер ответил off — раз в 2 мин), вход — cookie страницы из WKWebView.
final class Geo: NSObject, CLLocationManagerDelegate {
    static let shared = Geo()
    static let every: TimeInterval = 30, offEvery: TimeInterval = 120, maxFails = 3

    private let lm = CLLocationManager()
    private(set) var running = false
    private(set) var state = "wait"                 // on / off / wait / err / login / denied
    private(set) var sentAt: TimeInterval = 0
    private var nextAt: TimeInterval = 0
    private var busy = false
    private var loginFails = 0
    var onChange: (() -> Void)?

    override init() {
        super.init()
        lm.delegate = self
        lm.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        lm.distanceFilter = kCLDistanceFilterNone
        lm.activityType = .otherNavigation
        lm.pausesLocationUpdatesAutomatically = false
    }

    func start() {
        running = true
        loginFails = 0
        nextAt = 0
        switch lm.authorizationStatus {
        case .notDetermined: lm.requestWhenInUseAuthorization()          // дальше — locationManagerDidChangeAuthorization
        case .denied, .restricted: set("denied")
        default: begin()
        }
    }

    func stop() {
        running = false
        lm.stopUpdatingLocation()
        set("wait")
    }

    private func begin() {
        guard running else { return }
        lm.allowsBackgroundLocationUpdates = true
        lm.showsBackgroundLocationIndicator = true
        lm.startUpdatingLocation()
    }

    func locationManagerDidChangeAuthorization(_ m: CLLocationManager) {
        switch m.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways: begin()
        case .denied, .restricted: if running { set("denied") }
        default: break
        }
    }

    func locationManager(_ m: CLLocationManager, didUpdateLocations locs: [CLLocation]) {
        guard running, let l = locs.last, !busy, Date().timeIntervalSince1970 >= nextAt else { return }
        send(l)
    }

    func locationManager(_ m: CLLocationManager, didFailWithError e: Error) {
        if (e as? CLError)?.code == .denied { set("denied") }
    }

    private func set(_ s: String) {
        state = s
        DispatchQueue.main.async { self.onChange?() }
    }

    private func send(_ l: CLLocation) {
        guard let srv = Servers.current?.url, let url = URL(string: srv + "/api/courier/geo") else { return }
        busy = true
        let bg = UIApplication.shared.beginBackgroundTask(withName: "geo")
        WKWebsiteDataStore.default().httpCookieStore.getAllCookies { all in
            let host = url.host ?? ""
            let ck = all.filter { host == $0.domain || host.hasSuffix("." + $0.domain.trimmingCharacters(in: CharacterSet(charactersIn: "."))) }
                .map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
            var r = URLRequest(url: url, timeoutInterval: 20)
            r.httpMethod = "POST"
            r.setValue("application/json", forHTTPHeaderField: "Content-Type")
            r.setValue("1", forHTTPHeaderField: "X-Sklad")
            r.setValue("MiseCourier/\(WebController.version) iOS", forHTTPHeaderField: "User-Agent")
            if !ck.isEmpty { r.setValue(ck, forHTTPHeaderField: "Cookie") }
            r.httpBody = try? JSONSerialization.data(withJSONObject: ["lat": l.coordinate.latitude, "lon": l.coordinate.longitude,
                                                                      "acc": Int(l.horizontalAccuracy.rounded()), "src": "ios"])
            URLSession.shared.dataTask(with: r) { data, resp, err in
                DispatchQueue.main.async {
                    self.busy = false
                    let now = Date().timeIntervalSince1970
                    self.nextAt = now + Self.every
                    let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
                    if err != nil || code == 0 {
                        self.set("err")
                    } else if code == 401 || code == 403 {            // вышел, удалён или нет права — не крутимся впустую
                        self.loginFails += 1
                        self.set("login")
                        if self.loginFails >= Self.maxFails { self.stop(); self.state = "login" }
                    } else if code != 200 {
                        self.set("err")
                    } else {
                        self.loginFails = 0
                        let j = data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
                        if j?["off"] as? Bool == true {
                            self.nextAt = now + Self.offEvery
                            self.set("off")
                        } else {
                            self.sentAt = now
                            self.set("on")
                        }
                    }
                    UIApplication.shared.endBackgroundTask(bg)
                }
            }.resume()
        }
    }
}
