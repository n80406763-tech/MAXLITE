import SwiftUI
import WebKit

/// Открывает настоящий web.max.ru. Пользователь логинится там как обычно,
/// а мы после этого забираем из localStorage то, что положил сам сайт:
/// __oneme_auth (viewerId + token) и __oneme_device_id.
struct LoginView: View {
    var onAuth: (Auth) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var hint = "Войдите в свой аккаунт MAX"

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                AuthWebView(onAuth: onAuth)
                Text(hint)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            }
            .navigationTitle("Вход в MAX")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
            }
        }
    }
}

struct AuthWebView: UIViewRepresentable {
    var onAuth: (Auth) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onAuth: onAuth) }

    func makeUIView(context: Context) -> WKWebView {
        let cfg = WKWebViewConfiguration()
        cfg.websiteDataStore = .default()          // localStorage должен переживать перезагрузки
        let web = WKWebView(frame: .zero, configuration: cfg)
        web.navigationDelegate = context.coordinator
        web.load(URLRequest(url: URL(string: "https://web.max.ru")!))
        context.coordinator.attach(web)
        return web
    }

    func updateUIView(_ uiView: WKWebView, context: Context) { }

    static func dismantleUIView(_ uiView: WKWebView, coordinator: Coordinator) {
        coordinator.stop()
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        private let onAuth: (Auth) -> Void
        private weak var web: WKWebView?
        private var timer: Timer?
        private var done = false
        /// Уникальный маркер script message handler'а — у WKWebView их нельзя
        /// переиспользовать, а вью может пересоздаваться.
        private let handlerName = "maxliteAuth\(UUID().uuidString.prefix(8))"

        init(onAuth: @escaping (Auth) -> Void) { self.onAuth = onAuth }

        func attach(_ web: WKWebView) {
            self.web = web
            // Сайт сам знает, когда записал сессию в localStorage. Вмешиваться в
            // его код нельзя, но можно «подсмотреть» запись: подменяем setItem
            // вокруг оригинала и шлём уведомление в нативную часть. Так вместо
            // опроса раз в секунду мы просыпаемся только на реальное событие.
            let hook = """
            (function(){
              if (window.__maxliteHooked) return;
              window.__maxliteHooked = true;
              try {
                var orig = Storage.prototype.setItem;
                Storage.prototype.setItem = function(k, v) {
                  try {
                    if (k === '__oneme_auth' || k === '__oneme_device_id') {
                      window.webkit.messageHandlers.\(handlerName).postMessage(k);
                    }
                  } catch (e) {}
                  return orig.apply(this, arguments);
                };
              } catch (e) {}
            })()
            """
            let script = WKUserScript(source: hook, injectionTime: .atDocumentStart,
                                      forMainFrameOnly: false)
            web.configuration.userContentController.addUserScript(script)
            web.configuration.userContentController.add(self, name: handlerName)
            // Запасной вариант: редкий опрос на случай, если токен записался
            // до установки хука (или страница пересоздала Storage).
            timer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
                self?.poll()
            }
        }

        func stop() {
            timer?.invalidate()
            timer = nil
            web?.configuration.userContentController.removeScriptMessageHandler(forName: handlerName)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            probe(webView, "didFinish")
            poll()
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!,
                     withError error: Error) {
            #if DEBUG
            print("[MAXLITE] provisional fail:", error.localizedDescription)
            #endif
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            #if DEBUG
            print("[MAXLITE] nav fail:", error.localizedDescription)
            #endif
        }

        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            #if DEBUG
            print("[MAXLITE] web content process terminated")
            #endif
        }

        private func probe(_ web: WKWebView, _ tag: String) {
            let js = "JSON.stringify({u:location.href,t:document.title,"
                + "b:(document.body?document.body.innerText.length:-1),"
                + "h:(document.body?document.body.innerHTML.length:-1)})"
            web.evaluateJavaScript(js) { r, e in
                #if DEBUG
                print("[MAXLITE] \(tag):", r as? String ?? "nil", "err:", e?.localizedDescription ?? "-")
                #endif
            }
        }

        private func poll() {
            guard !done, let web else { return }
            let js = """
            (function(){try{return JSON.stringify({
              a: localStorage.getItem('__oneme_auth'),
              d: localStorage.getItem('__oneme_device_id')
            })}catch(e){return null}})()
            """
            web.evaluateJavaScript(js) { [weak self] result, _ in
                guard let self, !self.done,
                      let s = result as? String,
                      let data = s.data(using: .utf8),
                      let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let authRaw = obj["a"] as? String,
                      let authData = authRaw.data(using: .utf8),
                      let authObj = try? JSONSerialization.jsonObject(with: authData) as? [String: Any],
                      let token = authObj["token"] as? String, !token.isEmpty,
                      let viewer = (authObj["viewerId"] as? NSNumber)?.int64Value
                        ?? Int64((authObj["viewerId"] as? String) ?? "")
                else { return }

                // deviceId сайт хранит как JSON-строку, иногда — как голый UUID.
                var device = (obj["d"] as? String) ?? ""
                if let dd = device.data(using: .utf8),
                   let unq = try? JSONSerialization.jsonObject(
                        with: dd, options: [.fragmentsAllowed]) as? String {
                    device = unq
                }
                if device.isEmpty { device = UUID().uuidString }

                self.done = true
                self.stop()
                self.onAuth(Auth(viewerId: viewer, token: token, deviceId: device))
            }
        }
    }
}

extension AuthWebView.Coordinator: WKScriptMessageHandler {
    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        guard message.name == handlerName else { return }
        #if DEBUG
        print("[MAXLITE] localStorage write:", message.body)
        #endif
        poll()
    }
}
