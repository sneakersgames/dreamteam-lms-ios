import ConsentViewController
import GamesLib
import UIKit
import WebKit

/// Hosts the web game and bridges it to ghcore.
///
/// The web app has no header of its own in native mode, so this controller owns
/// the whole navigation bar, and it answers the web side's questions about the
/// user, environment and consent in place of the G-H-C web component.
final class GameWebViewController: UIViewController {

    /// Deep link the host opened the game with, forwarded on `env.get`.
    private let launchUrl: String?

    private var webView: WKWebView!
    private var bridge: GHBridge!

    /// Set once the web app reports `app.ready`. Events sent before this are
    /// still delivered, because the web side replays and queues them.
    private var isBridgeReady = false

    private lazy var errorView = makeErrorView()

    init(launchUrl: String? = nil) {
        self.launchUrl = launchUrl
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        webView?.configuration.userContentController
            .removeScriptMessageHandler(forName: GameConfig.messageHandlerName)
    }

    // MARK: Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .systemBackground
        setUpNavigationBar()
        setUpWebView()
        observeHostNotifications()
        load()
    }

    // MARK: Navigation bar

    private static let barColor = UIColor(red: 235 / 255, green: 23 / 255, blue: 1 / 255, alpha: 1)

    private func setUpNavigationBar() {
        title = "Last Man Standing"

        // Per-item appearance, so it wins over whatever the host app sets globally.
        let appearance = UINavigationBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = Self.barColor
        appearance.titleTextAttributes = [.foregroundColor: UIColor.white]
        appearance.largeTitleTextAttributes = [.foregroundColor: UIColor.white]
        navigationItem.standardAppearance = appearance
        navigationItem.scrollEdgeAppearance = appearance
        navigationItem.compactAppearance = appearance
        navigationItem.compactScrollEdgeAppearance = appearance

        navigationController?.navigationBar.tintColor = .white
        navigationController?.navigationBar.barStyle = .black

        navigationItem.leftBarButtonItem = UIBarButtonItem(
            image: UIImage(systemName: "line.3.horizontal"),
            style: .plain,
            target: self,
            action: #selector(openMenu)
        )
        navigationItem.leftBarButtonItem?.accessibilityLabel = "Open Menu"

        #if DEBUG
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: "Demo",
            style: .plain,
            target: self,
            action: #selector(openNativeDemo)
        )
        #endif
    }

    @objc private func openMenu() {
        GamingHubCards.openMenu()
    }

    #if DEBUG
    /// The original native reference implementation, kept for comparison. It is
    /// presented rather than pushed because it brings its own NavigationStack.
    @objc private func openNativeDemo() {
        let data = launchUrl.map { ["link": $0] }
        present(GameBody.hostingController(data: data), animated: true)
    }
    #endif

    // MARK: Web view

    private func setUpWebView() {
        let configuration = WKWebViewConfiguration()
        // Non-ephemeral, so the session cookie the web side installs survives
        // relaunch and the user gets a signed-in first paint.
        configuration.websiteDataStore = .default()
        configuration.applicationNameForUserAgent = GameConfig.userAgentSuffix
        configuration.allowsInlineMediaPlayback = true
        configuration.userContentController.add(
            WeakScriptMessageHandler(delegate: self),
            name: GameConfig.messageHandlerName
        )

        webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = self
        webView.uiDelegate = self
        // The web app locks the browser URL at "/" and drives its own
        // navigation, so there is no history to swipe through.
        webView.allowsBackForwardNavigationGestures = false
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(webView)
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        bridge = GHBridge(webView: webView)
    }

    /// Consent is only passed when the host actually holds it: the
    /// `_sp_pass_consent` flag makes the web CMP wait for injected consent, so
    /// sending it without `preloadConsent` would hang the banner.
    private func load() {
        errorView.isHidden = true

        let consents = AdsConsentManager.consent
        webView.load(URLRequest(url: GameConfig.launchURL(passConsent: consents != nil)))

        if let consents {
            webView.preloadConsent(from: consents)
        }
    }

    // MARK: Host notifications

    private func observeHostNotifications() {
        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(onLoginLogout), name: .ghLoggedIn, object: nil)
        center.addObserver(self, selector: #selector(onLoginLogout), name: .ghLoggedOut, object: nil)
        center.addObserver(self, selector: #selector(onDeepLink), name: .ghOpenLink, object: nil)
    }

    @objc private func onLoginLogout() {
        bridge.emit("user.changed", payload: BridgePayloads.user())
    }

    @objc private func onDeepLink(notification: Notification) {
        guard let url = Self.deepLinkURL(from: notification.userInfo),
              url.contains(GameConfig.gameId) else { return }

        bridge.emit("deeplink", payload: ["url": url])
    }

    /// The POC host posts a `link` string while the contract's sample uses a
    /// `url` URL, so both shapes are accepted.
    private static func deepLinkURL(from userInfo: [AnyHashable: Any]?) -> String? {
        guard let userInfo else { return nil }

        if let link = userInfo["link"] as? String { return link }
        if let url = userInfo["url"] as? URL { return url.absoluteString }
        if let url = userInfo["url"] as? String { return url }
        return nil
    }

    // MARK: Error state

    private func makeErrorView() -> UIView {
        let label = UILabel()
        label.text = "Couldn't load the game."
        label.font = .preferredFont(forTextStyle: .headline)
        label.textAlignment = .center

        let button = UIButton(type: .system)
        button.setTitle("Try Again", for: .normal)
        button.addTarget(self, action: #selector(retry), for: .touchUpInside)

        let stack = UIStackView(arrangedSubviews: [label, button])
        stack.axis = .vertical
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.isHidden = true

        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -24),
        ])
        return stack
    }

    @objc private func retry() {
        load()
    }
}

// MARK: - Bridge message routing

extension GameWebViewController: WKScriptMessageHandler {

    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        guard let message = BridgeMessage(body: message.body) else {
            bridgeLog.error("Discarding malformed bridge message")
            return
        }

        if let gameId = message.gameId, gameId != GameConfig.gameId {
            bridgeLog.warning("Message addressed to \(gameId, privacy: .public), build is \(GameConfig.gameId, privacy: .public)")
        }

        print("[ghbridge] inbound \(message.type) oneWay=\(message.oneWay)")

        switch message.type {
        // Requests: the web asks, we answer. Every one must get a reply, even
        // an error, or the web side times out and degrades to anonymous.
        case "env.get":
            print("[ghbridge] env.get sessionKeyLen=\(GameConfig.sessionKey?.count ?? 0)")
            bridge.reply(to: message, payload: BridgePayloads.environment(launchUrl: launchUrl))
        case "user.get":
            bridge.reply(to: message, payload: BridgePayloads.user())
        case "consent.get":
            bridge.reply(to: message, payload: BridgePayloads.consent())

        // Commands: the web tells, we act. No reply.
        case "app.ready":
            isBridgeReady = true
        case "auth.login":
            GamingHubCards.login(GameConfig.gameId)
        case "auth.register":
            GamingHubCards.register(GameConfig.gameId)
        case "auth.logout":
            GamingHubCards.logout()
        case "menu.open":
            open(menuTarget: message.payload?["target"] as? String)

        default:
            bridgeLog.warning("Unhandled bridge message \(message.type, privacy: .public)")
            if message.expectsReply {
                bridge.fail(message, error: "Unsupported message type: \(message.type)")
            }
        }
    }

    /// ghcore has a dedicated profile screen; the other targets have no
    /// equivalent, so they fall back to the menu the user can reach them from.
    private func open(menuTarget target: String?) {
        switch target {
        case "profile":
            GamingHubCards.openUefaProfile()
        default:
            GamingHubCards.openMenu()
        }
    }
}

// MARK: - Navigation

extension GameWebViewController: WKNavigationDelegate {

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        // A fresh document means a fresh window.__ghBridge.
        isBridgeReady = false
    }

    func webView(_ webView: WKWebView,
                 decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard navigationAction.navigationType == .linkActivated,
              let url = navigationAction.request.url,
              url.host != GameConfig.baseURL.host else {
            decisionHandler(.allow)
            return
        }

        // Anything off-site is the host app's business, not the game's.
        decisionHandler(.cancel)
        GamingHubCards.openLink(url.absoluteString, gameId: GameConfig.gameId)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        show(error)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        show(error)
    }

    private func show(_ error: Error) {
        // A cancelled load is usually us redirecting away, not a failure.
        if (error as NSError).code == NSURLErrorCancelled { return }

        bridgeLog.error("Navigation failed: \(error.localizedDescription, privacy: .public)")
        errorView.isHidden = false
    }
}

// MARK: - Pop-ups

extension GameWebViewController: WKUIDelegate {

    /// `target="_blank"` has no window to open into, so it goes to the host.
    func webView(_ webView: WKWebView,
                 createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction,
                 windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = navigationAction.request.url {
            GamingHubCards.openLink(url.absoluteString, gameId: GameConfig.gameId)
        }
        return nil
    }
}
