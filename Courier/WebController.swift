import UIKit
import WebKit

/// WKWebView со страницей курьера. window.MiseApp — тот же мост, что у Android (start/stop/status/version/servers/choose/change),
/// только вызовы идут сообщениями (webkit.messageHandlers.mise), а status() читает window.__miseStatus, который присылает приложение.
final class WebController: UIViewController, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
    static let shared = WebController()
    static let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"

    private(set) var web: WKWebView!

    override func loadView() {
        let cfg = WKWebViewConfiguration()
        cfg.allowsInlineMediaPlayback = true
        cfg.websiteDataStore = .default()
        cfg.applicationNameForUserAgent = "MiseCourier/\(Self.version) iOS"
        let js = """
        window.__miseStatus = {};
        window.MiseApp = {
          platform: "ios",
          version: () => \(json(Self.version)),
          servers: () => \(json(Servers.json)),
          server: () => location.protocol === "https:" ? location.origin : "",
          status: () => JSON.stringify(window.__miseStatus || {}),
          start: () => webkit.messageHandlers.mise.postMessage({cmd: "start"}),
          stop: () => webkit.messageHandlers.mise.postMessage({cmd: "stop"}),
          change: () => webkit.messageHandlers.mise.postMessage({cmd: "change"}),
          choose: u => webkit.messageHandlers.mise.postMessage({cmd: "choose", url: u})
        };
        """
        cfg.userContentController.addUserScript(WKUserScript(source: js, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        cfg.userContentController.add(self, name: "mise")
        web = WKWebView(frame: .zero, configuration: cfg)
        web.navigationDelegate = self
        web.uiDelegate = self
        web.allowsBackForwardNavigationGestures = true
        let container = UIView()
        container.backgroundColor = .systemBackground
        container.addSubview(web)
        web.translatesAutoresizingMaskIntoConstraints = false
        let safe = container.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            web.topAnchor.constraint(equalTo: safe.topAnchor),
            web.bottomAnchor.constraint(equalTo: safe.bottomAnchor),
            web.leadingAnchor.constraint(equalTo: safe.leadingAnchor),
            web.trailingAnchor.constraint(equalTo: safe.trailingAnchor)
        ])
        view = container
        Geo.shared.onChange = { [weak self] in self?.pushStatus() }
    }

    private func json(_ s: String) -> String {
        let d = try? JSONSerialization.data(withJSONObject: [s])
        let a = d.flatMap { String(data: $0, encoding: .utf8) } ?? "[\"\"]"
        return String(a.dropFirst().dropLast())
    }

    func openWorkspace() {
        loadViewIfNeeded()
        if let s = Servers.current, let u = URL(string: s.url + (s.start ?? "/courier")) {
            web.load(URLRequest(url: u))
        } else if let f = Bundle.main.url(forResource: "choose", withExtension: "html") {
            web.loadFileURL(f, allowingReadAccessTo: f.deletingLastPathComponent())
        }
    }

    func take(_ url: URL) {
        let q = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
        if url.scheme == "misecourier", url.host == "open", let s = Servers.known(q?.first { $0.name == "u" }?.value) {
            if s.url != Servers.current?.url { Geo.shared.stop(); Servers.current = s }
        }
        openWorkspace()
    }

    func pushStatus() {
        let st: [String: Any] = ["running": Geo.shared.running, "state": Geo.shared.state, "at": Geo.shared.sentAt * 1000]
        guard let d = try? JSONSerialization.data(withJSONObject: st), let s = String(data: d, encoding: .utf8) else { return }
        web?.evaluateJavaScript("window.__miseStatus = \(s);", completionHandler: nil)
    }

    func userContentController(_ uc: WKUserContentController, didReceive msg: WKScriptMessage) {
        guard msg.frameInfo.isMainFrame, let from = msg.frameInfo.request.url, own(from),
              let b = msg.body as? [String: Any], let cmd = b["cmd"] as? String else { return }
        if from.isFileURL {
            guard cmd == "choose", let s = Servers.known(b["url"] as? String) else { return }
            Geo.shared.stop()
            Servers.current = s
            openWorkspace()
            return
        }
        guard from.scheme == "https" else { return }
        switch cmd {
        case "start": Geo.shared.start()
        case "stop": Geo.shared.stop()
        case "change":
            Geo.shared.stop()
            Servers.current = nil
            openWorkspace()
        default: break
        }
        pushStatus()
    }

    private func own(_ url: URL?) -> Bool {
        guard let u = url else { return false }
        if u.isFileURL { return Servers.current == nil && u.standardizedFileURL == Bundle.main.url(forResource: "choose", withExtension: "html")?.standardizedFileURL }
        guard let server = Servers.current.flatMap({ URL(string: $0.url) }) else { return false }
        return u.scheme == "https" && u.host == server.host && (u.port ?? 443) == (server.port ?? 443)
    }

    // свой сервер — здесь; Яндекс Карты, t.me и прочее — наружу
    func webView(_ w: WKWebView, decidePolicyFor a: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if own(a.request.url) { decisionHandler(.allow); return }
        if a.targetFrame?.isMainFrame != false, let u = a.request.url { openExternal(u) }
        decisionHandler(.cancel)
    }

    // window.open: свой адрес — в этом же окне, чужой — наружу
    func webView(_ w: WKWebView, createWebViewWith c: WKWebViewConfiguration, for a: WKNavigationAction, windowFeatures f: WKWindowFeatures) -> WKWebView? {
        if let u = a.request.url {
            if own(u) { w.load(a.request) } else { openExternal(u) }
        }
        return nil
    }

    func webView(_ w: WKWebView, didFinish n: WKNavigation!) { pushStatus() }

    private func openExternal(_ url: URL) {
        if ["https", "http", "tel", "tg", "maps", "yandexmaps", "yandexnavi"].contains(url.scheme?.lowercased() ?? "") {
            UIApplication.shared.open(url)
        }
    }

    func webView(_ w: WKWebView, didFailProvisionalNavigation n: WKNavigation!, withError error: Error) {
        showLoadError(error)
    }

    func webView(_ w: WKWebView, didFail n: WKNavigation!, withError error: Error) {
        showLoadError(error)
    }

    private func showLoadError(_ error: Error) {
        let e = error as NSError
        guard e.domain == NSURLErrorDomain, e.code != NSURLErrorCancelled, presentedViewController == nil else { return }
        let alert = UIAlertController(title: "Не удалось открыть заказы", message: "Проверьте подключение к интернету.", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Повторить", style: .default) { _ in self.openWorkspace() })
        alert.addAction(UIAlertAction(title: "Другой город", style: .default) { _ in
            Geo.shared.stop()
            Servers.current = nil
            self.openWorkspace()
        })
        present(alert, animated: true)
    }

    // окна страницы: без них confirm() в WKWebView молча возвращает false — «Доставлен» не нажимался бы
    func webView(_ w: WKWebView, runJavaScriptAlertPanelWithMessage m: String, initiatedByFrame f: WKFrameInfo, completionHandler done: @escaping () -> Void) {
        let a = UIAlertController(title: nil, message: m, preferredStyle: .alert)
        a.addAction(UIAlertAction(title: "OK", style: .default) { _ in done() })
        present(a, animated: true)
    }

    func webView(_ w: WKWebView, runJavaScriptConfirmPanelWithMessage m: String, initiatedByFrame f: WKFrameInfo, completionHandler done: @escaping (Bool) -> Void) {
        let a = UIAlertController(title: nil, message: m, preferredStyle: .alert)
        a.addAction(UIAlertAction(title: "Отмена", style: .cancel) { _ in done(false) })
        a.addAction(UIAlertAction(title: "Да", style: .default) { _ in done(true) })
        present(a, animated: true)
    }

    func webView(_ w: WKWebView, runJavaScriptTextInputPanelWithPrompt p: String, defaultText t: String?, initiatedByFrame f: WKFrameInfo,
                 completionHandler done: @escaping (String?) -> Void) {
        let a = UIAlertController(title: nil, message: p, preferredStyle: .alert)
        a.addTextField { $0.text = t }
        a.addAction(UIAlertAction(title: "Отмена", style: .cancel) { _ in done(nil) })
        a.addAction(UIAlertAction(title: "OK", style: .default) { _ in done(a.textFields?.first?.text) })
        present(a, animated: true)
    }
}
