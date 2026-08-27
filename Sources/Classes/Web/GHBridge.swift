import Foundation
import OSLog
import WebKit

let bridgeLog = Logger(subsystem: "com.dreamteam.epllastmanstanding", category: "ghbridge")

/// A message posted by the web app to `window.webkit.messageHandlers.ghbridge`.
struct BridgeMessage {
    let version: Int
    let id: String?
    let type: String
    let oneWay: Bool
    let gameId: String?
    let payload: [String: Any]?

    /// Messages arrive as a JS object literal, which WebKit hands over as a
    /// dictionary. Anything without a `type` is not addressed to this protocol.
    init?(body: Any) {
        guard let body = body as? [String: Any],
              let type = body["type"] as? String else { return nil }

        self.version = body["v"] as? Int ?? GameConfig.protocolVersion
        self.id = body["id"] as? String
        self.type = type
        self.oneWay = body["oneWay"] as? Bool ?? false
        self.gameId = body["gameId"] as? String
        self.payload = body["payload"] as? [String: Any]
    }

    /// A request expects exactly one reply echoing its id; a command expects none.
    var expectsReply: Bool { oneWay == false && id != nil }
}

/// Serialises outbound traffic and hands it to `window.__ghBridge.receive`.
final class GHBridge {
    private weak var webView: WKWebView?

    init(webView: WKWebView) {
        self.webView = webView
    }

    // MARK: Replies

    func reply(to message: BridgeMessage, payload: Any?) {
        guard let id = message.id else { return }
        send(["id": id, "ok": true, "payload": payload ?? NSNull()])
    }

    func fail(_ message: BridgeMessage, error: String) {
        guard let id = message.id else { return }
        bridgeLog.error("Replying with error to \(message.type, privacy: .public): \(error, privacy: .public)")
        send(["id": id, "ok": false, "error": error])
    }

    // MARK: Events

    func emit(_ type: String, payload: Any?) {
        send(["type": type, "payload": payload ?? NSNull()])
    }

    // MARK: Transport

    /// The web side accepts a JSON string, which avoids having to build a JS
    /// object literal by hand. `window.__ghBridge` only exists once the web
    /// app's first client code has run, so its absence is not an error.
    func send(_ body: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: body),
              let json = String(data: data, encoding: .utf8) else {
            bridgeLog.error("Failed to serialise outbound bridge message")
            return
        }

        let escaped = Self.escapeForSingleQuotedJS(json)
        let script = "window.__ghBridge && window.__ghBridge.receive('\(escaped)')"

        DispatchQueue.main.async { [weak webView] in
            webView?.evaluateJavaScript(script) { _, error in
                if let error {
                    bridgeLog.error("receive() failed: \(error.localizedDescription, privacy: .public)")
                }
            }
        }
    }

    /// U+2028 and U+2029 are valid in JSON but terminate a JavaScript string
    /// literal, and JSONSerialization emits them raw.
    static func escapeForSingleQuotedJS(_ json: String) -> String {
        json
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
            .replacingOccurrences(of: "\u{2028}", with: "\\u2028")
            .replacingOccurrences(of: "\u{2029}", with: "\\u2029")
    }
}

/// `WKUserContentController` retains its message handlers strongly, so
/// registering a view controller directly leaks it for the lifetime of the
/// configuration. This forwards weakly instead.
final class WeakScriptMessageHandler: NSObject, WKScriptMessageHandler {
    private weak var delegate: WKScriptMessageHandler?

    init(delegate: WKScriptMessageHandler) {
        self.delegate = delegate
    }

    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        delegate?.userContentController(userContentController, didReceive: message)
    }
}
