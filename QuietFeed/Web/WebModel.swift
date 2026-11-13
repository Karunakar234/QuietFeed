import AVFAudio
import Foundation
import Observation
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif
import WebKit

/// Owns one filtered web view: one platform, one account, the rules that are switched on.
@MainActor
@Observable
final class WebModel: NSObject {
    let platform: Platform
    private(set) var state: WebState = .loading(progress: 0)
    private(set) var isSingleItem = false
    private(set) var canGoBack = false
    private(set) var isVideoFullscreen = false
    /// True while the person is scrolling down through the page: the screen hides its own bar
    /// and margins so the site gets the whole screen, leaving just a Close button.
    private(set) var isImmersive = false

    @ObservationIgnored private(set) var webView: WKWebView!
    @ObservationIgnored private var navGuard: NavigationGuard
    /// The first page to load, when it isn't the platform's home.
    @ObservationIgnored private let startURL: URL?
    @ObservationIgnored private let insights: WeeklyInsightsStore
    @ObservationIgnored private var observations: [NSKeyValueObservation] = []
    @ObservationIgnored private var lastScrollY: CGFloat = 0
    /// How far the current scroll has gone in one direction (positive = down the page).
    @ObservationIgnored private var scrollRun: CGFloat = 0
    #if canImport(UIKit)
    @ObservationIgnored private var refreshControl: UIRefreshControl?
    #endif

    private static let engineSource: String = {
        guard let url = Bundle.main.url(forResource: "FilterEngine", withExtension: "js"),
              let source = try? String(contentsOf: url, encoding: .utf8) else {
            assertionFailure("FilterEngine.js missing from the bundle")
            return ""
        }
        return source
    }()

    init(
        platform: Platform,
        dataStoreID: UUID,
        rules: [FilterRule],
        startURL: URL? = nil,
        insights: WeeklyInsightsStore
    ) {
        self.platform = platform
        self.startURL = startURL
        self.insights = insights
        self.navGuard = NavigationGuard(platform: platform, rules: rules)
        super.init()

        let config = WKWebViewConfiguration()
        config.websiteDataStore = WKWebsiteDataStore(forIdentifier: dataStoreID)
        // WKWebView disables the HTML element Fullscreen API by default. YouTube and
        // YouTube Music check this preference before enabling their full-screen control.
        // iPhone/iPad then use WebKit's native controller; Mac is customized below.
        if Self.videoPlatformIDs.contains(platform.id) {
            config.preferences.isElementFullscreenEnabled = true
        }
        #if !os(macOS)
        config.allowsInlineMediaPlayback = true
        config.allowsPictureInPictureMediaPlayback = true
        #endif
        config.allowsAirPlayForMediaPlayback = true
        // Add the Safari identity only on iPhone and iPad. Appending a mobile Safari token to
        // WebKit's desktop Mac user agent creates a mixed, unsupported identity that YouTube and
        // YouTube Music can reject before rendering.
        if !Self.isRunningOnMac {
            config.applicationNameForUserAgent = "Version/17.0 Mobile/15E148 Safari/604.1"
        }
        config.userContentController.add(WeakMessageHandler(target: self), name: "stillfeed")
        installScripts(rules, into: config.userContentController)

        let view = WKWebView(frame: .zero, configuration: config)
        if Self.videoPlatformIDs.contains(platform.id) {
            #if canImport(UIKit)
            view.underPageBackgroundColor = .black
            #elseif canImport(AppKit)
            view.underPageBackgroundColor = .black
            #endif
        }
        if Self.isRunningOnMac {
            view.customUserAgent = Self.macSafariUserAgent
        }
        view.navigationDelegate = self
        view.uiDelegate = self
        view.allowsBackForwardNavigationGestures = true
        webView = view
        #if DEBUG
        // Lets Safari's Web Inspector (Develop menu) inspect the page in debug builds.
        view.isInspectable = true
        #endif

        #if canImport(UIKit)
        // Pull down at the top of the page to reload, since Reload is out of sight while browsing.
        let refresh = UIRefreshControl()
        refresh.addAction(UIAction { [weak self] _ in self?.reload() }, for: .valueChanged)
        view.scrollView.refreshControl = refresh
        refreshControl = refresh
        #endif

        var obs = [
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
        #if canImport(UIKit)
        obs.append(view.scrollView.observe(\.contentOffset, options: [.new]) { [weak self] _, change in
            let y = change.newValue?.y ?? 0
            MainActor.assumeIsolated {
                self?.scrolled(to: y)
            }
        })
        #endif
        observations = obs
        // Load only after the ad rules are attached, so the first page request is filtered too.
        Task { @MainActor in
            await AdBlocker.install(into: config.userContentController)
            load(startURL ?? platform.baseUrl)
        }
    }

    private static var isRunningOnMac: Bool {
        #if os(macOS) || targetEnvironment(macCatalyst)
        true
        #elseif canImport(UIKit)
        ProcessInfo.processInfo.isiOSAppOnMac
        #else
        false
        #endif
    }

    /// A coherent desktop Safari identity for native Mac, Catalyst, and iPad apps running on Mac.
    private static let macSafariUserAgent =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 " +
        "(KHTML, like Gecko) Version/18.0 Safari/605.1.15"

    private static let videoPlatformIDs: Set<String> = [
        "youtube", "youtube_music", "netflix", "amazon_prime"
    ]

    func loadHome() {
        load(platform.baseUrl)
    }

    private func load(_ url: URL) {
        state = .loading(progress: 0)
        webView.load(URLRequest(url: url))
    }

    func reload() {
        state = .loading(progress: 0)
        isImmersive = false
        if webView.url == nil { loadHome() } else { webView.reload() }
    }

    /// Immediately silences the page before its SwiftUI container disappears. WebKit processes
    /// can outlive their view briefly, so relying on deallocation alone lets audio continue.
    func shutdown() {
        webView.evaluateJavaScript("""
        document.querySelectorAll('video, audio').forEach(function (media) {
          media.pause();
          media.removeAttribute('autoplay');
        });
        """)
        webView.setAllMediaPlaybackSuspended(true, completionHandler: nil)
        webView.stopLoading()
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "stillfeed")
    }

    func goBack() {
        if webView.canGoBack { webView.goBack() } else { loadHome() }
    }

    /// Plays or pauses the page's video. The mini-player's button, since the page's own
    /// controls are too small to use there.
    func togglePlayback() {
        webView.evaluateJavaScript("""
        (function () {
          var media = document.querySelector('video');
          if (!media) return;
          if (media.paused) { media.play().catch(function () {}); } else { media.pause(); }
        })();
        """)
    }

    private var playsInBackground: Bool { platform.id == "youtube" || platform.id == "youtube_music" }

    /// Called as the app starts leaving the foreground, before iOS pauses anything: remembers
    /// which media the person actually has playing, so a paused song stays paused.
    func notePlaybackBeforeBackground() {
        guard playsInBackground else { return }
        webView.evaluateJavaScript("""
        document.querySelectorAll('video, audio').forEach(function (media) {
          media.__quietfeedWasPlaying = !media.paused && !media.ended;
        });
        """)
    }

    /// Called once the app is in the background: keeps going only what was playing a moment ago.
    /// The audio session is activated only then, because a playback session interrupts other
    /// apps' audio, and leaving QuietFeed with a paused video shouldn't stop someone's music.
    func continuePlaybackInBackground() {
        guard playsInBackground else { return }
        let source = """
        (function () {
          var resumed = 0;
          document.querySelectorAll('video, audio').forEach(function (media) {
            if (!media.__quietfeedWasPlaying) return;
            resumed++;
            if (media.paused) media.play().catch(function () {});
          });
          return resumed;
        })();
        """
        webView.evaluateJavaScript(source) { [weak self] result, _ in
            guard let self, let resumed = result as? Int, resumed > 0 else { return }
            #if canImport(AVFAudio) && !os(macOS)
            AVAudioSession.sharedInstance().activate { _, _ in }
            #endif
            self.webView.setAllMediaPlaybackSuspended(false, completionHandler: nil)
        }
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
        // Streaming players commonly live in child frames. Install the engine in every frame
        // for video services so playback-ad controls are visible to the skipper.
        let mainFrameOnly = !Self.videoPlatformIDs.contains(platform.id)
        controller.addUserScript(WKUserScript(
            source: source,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: mainFrameOnly
        ))
        // iPhone and iPad must keep WebKit's native video full-screen controller. The
        // in-window override exists only for Mac, where the app intentionally keeps video
        // inside its own window instead of opening a separate WebKit presentation.
        if Self.isRunningOnMac && Self.videoPlatformIDs.contains(platform.id) {
            controller.addUserScript(WKUserScript(
                source: Self.inWindowFullscreenSource,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: true
            ))
        }
        if platform.id == "youtube" || platform.id == "youtube_music" {
            controller.addUserScript(WKUserScript(
                source: Self.keepVisibleSource,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: true
            ))
        }
        if platform.id == "youtube_music" {
            controller.addUserScript(WKUserScript(
                source: Self.trackControlsSource,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: true
            ))
        }
    }

    /// The lock screen and Control Center build their buttons from the page's media session:
    /// seek handlers give ±10 second buttons, track handlers give next and previous song.
    /// For YouTube Music this drops the seek handlers and makes sure there are track handlers,
    /// using YouTube Music's own if it registers them, or pressing its Next/Previous buttons if not.
    private static let trackControlsSource = """
    (function () {
      var session = navigator.mediaSession;
      if (!session || typeof session.setActionHandler !== 'function') return;
      var original = session.setActionHandler.bind(session);
      var pageHas = { nexttrack: false, previoustrack: false };
      function set(action, handler) {
        try { original(action, handler); } catch (e) { /* action not supported here */ }
      }

      session.setActionHandler = function (action, handler) {
        if (action === 'seekforward' || action === 'seekbackward') return set(action, null);
        if (action in pageHas) pageHas[action] = !!handler;
        return set(action, handler);
      };

      var buttons = {
        nexttrack: ['.next-button', 'button[aria-label="Next"]', 'button[aria-label="Next song"]'],
        previoustrack: ['.previous-button', 'button[aria-label="Previous"]', 'button[aria-label="Previous song"]']
      };
      function press(selectors) {
        for (var i = 0; i < selectors.length; i++) {
          var button = document.querySelector(selectors[i]);
          if (button) { button.click(); return; }
        }
      }
      function useTrackControls() {
        set('seekforward', null);
        set('seekbackward', null);
        Object.keys(buttons).forEach(function (action) {
          if (!pageHas[action]) set(action, function () { press(buttons[action]); });
        });
      }

      // Media "play" events don't bubble, so listen in the capture phase. Each new song reapplies it.
      document.addEventListener('play', useTrackControls, true);
      useTrackControls();
    })();
    """

    /// YouTube pauses its player when the page reports that it's hidden, which is what iOS
    /// tells it when QuietFeed goes to the background. This keeps the page reporting "visible"
    /// so music carries on (with the audio background mode in Info.plist). Only the visibility
    /// signal is touched; focus, blur and unload behave as normal.
    private static let keepVisibleSource = """
    (function () {
      var props = { hidden: false, webkitHidden: false, visibilityState: 'visible', webkitVisibilityState: 'visible' };
      Object.keys(props).forEach(function (name) {
        try {
          Object.defineProperty(document, name, { configurable: true, get: function () { return props[name]; } });
        } catch (e) { /* leave the browser's own value */ }
      });
      ['visibilitychange', 'webkitvisibilitychange'].forEach(function (type) {
        window.addEventListener(type, function (event) { event.stopImmediatePropagation(); }, true);
      });
    })();
    """

    /// WebKit's native element full screen detaches the web view into a separate macOS
    /// presentation. Keep YouTube's player inside QuietFeed's existing window instead.
    private static let inWindowFullscreenSource = """
    (function () {
      var activeElement = null;
      var savedStyle = null;

      function ensureStyle() {
        if (document.getElementById('quietfeed-fullscreen-style')) return;
        var fullscreenStyle = document.createElement('style');
        fullscreenStyle.id = 'quietfeed-fullscreen-style';
        fullscreenStyle.textContent = `
          html.quietfeed-fullscreen, html.quietfeed-fullscreen body {
            background: #000 !important;
            overflow: hidden !important;
          }
          .quietfeed-in-window-fullscreen,
          .quietfeed-in-window-fullscreen video {
            background: #000 !important;
          }
          .quietfeed-in-window-fullscreen video {
            object-fit: contain !important;
          }
        `;
        (document.head || document.documentElement).appendChild(fullscreenStyle);
      }

      function notify() {
        document.dispatchEvent(new Event('fullscreenchange'));
        document.dispatchEvent(new Event('webkitfullscreenchange'));
        try {
          window.webkit.messageHandlers.stillfeed.postMessage({ type: 'videoFullscreen', active: !!activeElement });
        } catch (error) { /* The native bridge may not be ready during teardown. */ }
      }

      function enter(element) {
        if (!element || activeElement === element) return Promise.resolve();
        if (activeElement) exit();
        ensureStyle();
        activeElement = element;
        savedStyle = element.getAttribute('style');
        document.documentElement.classList.add('quietfeed-fullscreen');
        element.classList.add('quietfeed-in-window-fullscreen');
        Object.assign(element.style, {
          position: 'fixed', inset: '0', width: '100vw', height: '100vh',
          maxWidth: 'none', maxHeight: 'none', margin: '0', zIndex: '2147483647',
          background: '#000', boxShadow: '0 0 0 100vmax #000'
        });
        document.documentElement.style.background = '#000';
        document.body.style.background = '#000';
        document.body.style.overflow = 'hidden';
        notify();
        return Promise.resolve();
      }

      function exit() {
        if (!activeElement) return Promise.resolve();
        activeElement.classList.remove('quietfeed-in-window-fullscreen');
        if (savedStyle === null) activeElement.removeAttribute('style');
        else activeElement.setAttribute('style', savedStyle);
        activeElement = null;
        savedStyle = null;
        document.documentElement.classList.remove('quietfeed-fullscreen');
        document.body.style.overflow = '';
        notify();
        return Promise.resolve();
      }

      try {
        Object.defineProperty(Document.prototype, 'fullscreenEnabled', { configurable: true, get: function () { return true; } });
        Object.defineProperty(Document.prototype, 'webkitFullscreenEnabled', { configurable: true, get: function () { return true; } });
        Object.defineProperty(Document.prototype, 'fullscreenElement', { configurable: true, get: function () { return activeElement; } });
        Object.defineProperty(Document.prototype, 'webkitFullscreenElement', { configurable: true, get: function () { return activeElement; } });
        Object.defineProperty(Element.prototype, 'requestFullscreen', { configurable: true, value: function () { return enter(this); } });
        Object.defineProperty(Element.prototype, 'webkitRequestFullscreen', { configurable: true, value: function () { return enter(this); } });
        Object.defineProperty(Document.prototype, 'exitFullscreen', { configurable: true, value: exit });
        Object.defineProperty(Document.prototype, 'webkitExitFullscreen', { configurable: true, value: exit });
      } catch (error) { /* Keep WebKit's implementation if a property cannot be replaced. */ }

      document.addEventListener('keydown', function (event) {
        if (event.key === 'Escape' && activeElement) {
          event.preventDefault();
          exit();
        }
      }, true);
    })();
    """

    private static func json(_ rules: [FilterRule]) -> String {
        guard let data = try? JSONEncoder.rules.encode(rules), let text = String(data: data, encoding: .utf8) else { return "[]" }
        return text
    }

    private func progressChanged(_ value: Double) {
        if case .loading = state { state = .loading(progress: value) }
    }

    private func urlChanged(_ url: URL?) {
        isSingleItem = navGuard.isSingleItem(url: url)
        // A new page starts with the bar showing, so there's never a page without controls.
        isImmersive = false
    }

    /// Hides the bar after scrolling ~30pt down the page, and shows it after ~40pt back up or
    /// near the top, as Safari does. Distance is added up over the whole scroll in one direction
    /// (offset updates arrive every frame, a few points at a time). Only the person's own
    /// scrolling counts: when the bar hides the page gets taller and its offset can shift,
    /// and reacting to that would make the bar flicker.
    private func scrolled(to y: CGFloat) {
        #if canImport(UIKit)
        let scrollView = webView.scrollView
        let delta = y - lastScrollY
        lastScrollY = y
        guard scrollView.isTracking || scrollView.isDragging || scrollView.isDecelerating else {
            scrollRun = 0
            return
        }
        // Keep adding while the direction holds; start over when it reverses.
        scrollRun = (delta >= 0) == (scrollRun >= 0) ? scrollRun + delta : delta

        let immersive: Bool
        if y < 40 {
            immersive = false
        } else if scrollRun > 30 {
            immersive = true
        } else if scrollRun < -40 {
            immersive = false
        } else {
            return
        }
        if immersive != isImmersive { isImmersive = immersive }
        #endif
    }

    fileprivate func handleMessage(_ body: Any) {
        guard let message = body as? [String: Any], let type = message["type"] as? String else { return }
        switch type {
        case "hidden":
            guard let count = message["count"] as? NSNumber else { return }
            insights.recordHidden(count.intValue)
        case "videoFullscreen":
            isVideoFullscreen = (message["active"] as? Bool) ?? false
        default:
            return
        }
    }

    private func fail(_ error: Error) {
        #if canImport(UIKit)
        refreshControl?.endRefreshing()
        #endif
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
            #if canImport(UIKit)
            await UIApplication.shared.open(outside)
            #elseif canImport(AppKit)
            NSWorkspace.shared.open(outside)
            #endif
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
        #if canImport(UIKit)
        refreshControl?.endRefreshing()
        #endif
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
            case .external(let outside):
                #if canImport(UIKit)
                UIApplication.shared.open(outside)
                #elseif canImport(AppKit)
                NSWorkspace.shared.open(outside)
                #endif
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
