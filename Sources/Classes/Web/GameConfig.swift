import Foundation

/// Static configuration for the web game and its native bridge.
enum GameConfig {
    /// The GAMEID this build identifies itself as, used for login flows and
    /// to decide whether an incoming deep link is addressed to us.
    static let gameId = "epllastmanstanding"

    /// HTTPS is used deliberately: the host 301-redirects plain HTTP, so going
    /// straight to HTTPS avoids needing an App Transport Security exception.
    static let baseURL = URL(string: "https://lms.uat-dreamteamfc.com/")!

    /// Appended to the User-Agent so requests arriving without `gh_native` are
    /// still identifiable as native traffic.
    static let userAgentSuffix = "DreamTeamNative/1.0 (ios)"

    /// Bridge protocol version, matching `app/lib/native/messages.ts`.
    static let protocolVersion = 1

    /// Name of the `WKScriptMessageHandler` the web side posts to.
    static let messageHandlerName = "ghbridge"

    /// Shared secret authorising `/api/auth/native-session`, supplied by the
    /// host app so it never appears in the URL or the document. Must match the
    /// server's `NATIVE_SESSION_SECRET`.
    static var sessionKey: String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: "GHNativeSessionKey") as? String,
              value.isEmpty == false else { return nil }
        return value
    }

    /// The initial URL, which carries the consent hand-off flag only when the
    /// host actually holds consent to pass.
    static func launchURL(passConsent: Bool) -> URL {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
        var items = [URLQueryItem(name: "gh_native", value: "ios")]
        if passConsent {
            items.append(URLQueryItem(name: "_sp_pass_consent", value: "true"))
        }
        components.queryItems = items
        return components.url ?? baseURL
    }
}
