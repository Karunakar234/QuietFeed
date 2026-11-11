import AVFAudio
import Foundation
import Observation
import UIKit
import WebKit

/// Owns one filtered web view: one platform, one account, the rules that are switched on.
@MainActor
@Observable
final class WebModel: NSObject {
    let platform: Platform
    private(set) var state: WebState = .loading(progress: 0)
    private(set) var isSingleItem = false
    private(set) var canGoBack = false

    @ObservationIgnored private(set) var webView: WKWebView!
    @ObservationIgnored private var navGuard: NavigationGuard
    @ObservationIgnored private var observations: [NSKeyValueObservation] = []

    private static let engineSource: String = {
        guard let url = Bundle.main.url(forResource: "FilterEngine", withExtension: "js"),
              let source = try? String(contentsOf: url, encoding: .utf8) else {
            assertionFailure("FilterEngine.js missing from the bundle")
            return ""
        }
        return source
    }()

    init(platform: Platform, dataStoreID: UUID, rules: [FilterRule]) {
        self.platform = platform
        self.navGuard = NavigationGuard(platform: platform, rules: rules)
        super.init()

        let config = WKWebViewConfiguration()
        config.websiteDataStore = WKWebsiteDataStore(forIdentifier: dataStoreID)
        config.allowsInlineMediaPlayback = true
        config.allowsPictureInPictureMediaPlayback = true
        config.allowsAirPlayForMediaPlayback = true
        // Present as ordinary mobile Safari so sign-in pages behave as they do there.
        config.applicationNameForUserAgent = "Version/17.0 Mobile/15E148 Safari/604.1"
        config.userContentController.add(WeakMessageHandler(target: self), name: "stillfeed")
        installScripts(rules, into: config.userContentController)

        let view = WKWebView(frame: .zero, configuration: config)
        view.navigationDelegate = self
        view.uiDelegate = self
        view.allowsBackForwardNavigationGestures = true
        webView = view
        #if DEBUG
        // Lets Safari's Web Inspector (Develop menu) inspect the page in debug builds.
        view.isInspectable = true
        #endif

        observations = [
            view.observe(\.estimatedProgress, options: [.new]) { [weak self] _, change in
                let value = change.newValue ?? 0
                MainActor.assumeIsolated {
                    self?.progressChanged(value)
                }
            },
            view.observe(\.url, options: [.new]) { [weak self] _, change in
                let value = change.newValue ?? nil
                MainActor.assumeIsolated {
                    self?.urlChanged(value)
                }
            },
            view.observe(\.canGoBack, options: [.new]) { [weak self] _, change in
                let value = change.newValue ?? false
                MainActor.assumeIsolated {
                    self?.canGoBack = value
                }
            }
        ]
        // Load only after the ad rules are attached, so the first page request is filtered too.
        Task { @MainActor in
            await AdBlocker.install(into: config.userContentController)
            loadHome()
        }
    }

    func loadHome() {
        state = .loading(progress: 0)
        webView.load(URLRequest(url: platform.baseUrl))
    }

    func reload() {
        state = .loading(progress: 0)
        if webView.url == nil { loadHome() } else { webView.reload() }
    }

    func goBack() {
        if webView.canGoBack { webView.goBack() } else { loadHome() }
    }

    func continuePlaybackInBackground() {
        guard platform.id == "youtube" || platform.id == "youtube_music" else { return }
        AVAudioSession.sharedInstance().activate { _, _ in }
        webView.setAllMediaPlaybackSuspended(false, completionHandler: nil)
        let source = """
        document.querySelectorAll('video, audio').forEach(function (media) {
          if (media.currentTime > 0 && !media.ended) media.play().catch(function () {});
        });
        """
        webView.evaluateJavaScript(source)
    }

    /// Called when a switch changes on the Filters screen. Applies to the open page at once.
    func updateRules(_ rules: [FilterRule]) {
        navGuard = NavigationGuard(platform: platform, rules: rules)
        let controller = webView.configuration.userContentController
        controller.removeAllUserScripts()
        installScripts(rules, into: controller)
        webView.evaluateJavaScript("window.__stillfeed && window.__stillfeed.update(\(Self.json(rules)));")
        isSingleItem = navGuard.isSingleItem(url: webView.url)
    }

    private func installScripts(_ rules: [FilterRule], into controller: WKUserContentController) {
        let source = Self.engineSource + "\nwindow.__stillfeed && window.__stillfeed.boot(\(Self.json(rules)));"
        let mainFrameOnly = platform.id != "youtube" && platform.id != "youtube_music"
        controller.addUserScript(WKUserScript(
            source: source,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: mainFrameOnly
        ))
    }

    private static func json(_ rules: [FilterRule]) -> String {
        guard let data = try? JSONEncoder.rules.encode(rules), let text = String(data: data, encoding: .utf8) else { return "[]" }
        return text
    }

    private func progressChanged(_ value: Double) {
        if case .loading = state { state = .loading(progress: value) }
    }

    private func urlChanged(_ url: URL?) {
        isSingleItem = navGuard.isSingleItem(url: url)
    }

    fileprivate func handleMessage(_ body: Any) {
        // The engine reports what it hid or blocked. Nothing is stored or sent anywhere yet;
        // /replica-backend uses this for the "report a problem" flow.
    }

    private func fail(_ error: Error) {
        let code = (error as NSError).code
        if code == NSURLErrorCancelled { return }
        // 102: "frame load interrupted" is what WebKit reports when we cancel a load ourselves.
        if (error as NSError).domain == "WebKitErrorDomain" && code == 102 { return }
        let offline = [NSURLErrorNotConnectedToInternet, NSURLErrorNetworkConnectionLost, NSURLErrorDataNotAllowed]
        state = offline.contains(code) ? .offline : .error("Check your connection and try again.")
    }
}

extension WebModel: WKNavigationDelegate {
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
        guard let url = navigationAction.request.url else { return .cancel }
        let isMainFrame = navigationAction.targetFrame?.isMainFrame ?? true
        switch navGuard.decide(url: url, isMainFrame: isMainFrame) {
        case .allow:
            return .allow
        case .redirect(let destination):
            webView.load(URLRequest(url: destination))
            return .cancel
        case .external(let outside):
            await UIApplication.shared.open(outside)
            return .cancel
        case .cancel:
            return .cancel
        }
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        state = .loading(progress: webView.estimatedProgress)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        state = .loaded
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        fail(error)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        fail(error)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        reload()
    }
}

extension WebModel: WKUIDelegate {
    /// Links that ask for a new window open in this one, through the same checks.
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = navigationAction.request.url {
            switch navGuard.decide(url: url, isMainFrame: true) {
            case .allow: webView.load(URLRequest(url: url))
            case .redirect(let destination): webView.load(URLRequest(url: destination))
            case .external(let outside): UIApplication.shared.open(outside)
            case .cancel: break
            }
        }
        return nil
    }
}

/// WKUserContentController keeps a strong reference to its handler; this breaks the cycle.
@MainActor
private final class WeakMessageHandler: NSObject, WKScriptMessageHandler {
    weak var target: WebModel?

    init(target: WebModel) {
        self.target = target
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.handleMessage(message.body)
    }
}
