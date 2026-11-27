import UIKit

/// Приложение курьера для iPhone: страница <сервер>/courier в WKWebView + геопозиция в фоне (Geo). Аналог courier_app (Android).
@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?

    func application(_ app: UIApplication, didFinishLaunchingWithOptions opts: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        window = UIWindow(frame: UIScreen.main.bounds)
        window?.rootViewController = WebController.shared
        window?.makeKeyAndVisible()
        if let url = opts?[.url] as? URL { WebController.shared.take(url) } else { WebController.shared.openWorkspace() }
        return true
    }

    /// misecourier://open?u=<адрес сервера> — со страницы курьера в Safari
    func application(_ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey: Any] = [:]) -> Bool {
        WebController.shared.take(url)
        return true
    }
}

/// Серверы, вшитые при сборке (servers.json: основной, регионы, демо); выбранный — в UserDefaults.
enum Servers {
    struct Item: Codable { let name: String; let url: String; let rests: [String]?; let start: String? }

    static let all: [Item] = {
        guard let f = Bundle.main.url(forResource: "servers", withExtension: "json"), let d = try? Data(contentsOf: f) else { return [] }
        return (try? JSONDecoder().decode([Item].self, from: d)) ?? []
    }()

    static var current: Item? {
        get { all.first { $0.url == UserDefaults.standard.string(forKey: "server") } }
        set { UserDefaults.standard.set(newValue?.url, forKey: "server") }
    }

    static func known(_ url: String?) -> Item? {
        guard let u = url?.replacingOccurrences(of: "/+$", with: "", options: .regularExpression) else { return nil }
        return all.first { $0.url == u }
    }

    static var json: String { String(data: (try? JSONEncoder().encode(all)) ?? Data("[]".utf8), encoding: .utf8) ?? "[]" }
}
