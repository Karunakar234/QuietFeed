import AVFAudio
import Foundation
import Observation
import os
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
    /// Where YouTube Music's own top bar keeps the slot QuietFeed's controls sit in.
    private(set) var siteNavAnchor: SiteNavAnchor = .missing
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
    /// When the person last tapped a link in the page; leaving the app needs a recent tap.
    @ObservationIgnored private var lastLinkTap: Date?
    private static let externalLinkGrace: TimeInterval = 10
    /// When the page's web content process last ended unexpectedly, within `crashWindow`.
    @ObservationIgnored private var processTerminations: [Date] = []
    private static let crashWindow: TimeInterval = 60
    private static let maxCrashReloads = 2
    /// Automatic retries used since the last successful load (see `LoadFailurePolicy`).
    @ObservationIgnored private var failedAttempts = 0
    @ObservationIgnored private var retryTask: Task<Void, Never>?
    /// Page loads as signpost intervals, so Instruments (os_signpost / Points of Interest)
    /// shows how long each platform takes from navigation start to finish or failure.
    private static let signposter = OSSignposter(subsystem: "com.kanna.quietfeed", category: .pointsOfInterest)
    @ObservationIgnored private var loadInterval: OSSignpostIntervalState?

    private func endLoadInterval(_ outcome: StaticString) {
        guard let loadInterval else { return }
        Self.signposter.endInterval("Page load", loadInterval, "\(outcome)")
        self.loadInterval = nil
    }
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
        load(startURL ?? platform.baseUrl)
    }

    /// The account whose website data this page uses.
    var dataStoreID: UUID? { webView.configuration.websiteDataStore.identifier }

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

    /// Platforms whose pages play video: full screen, Picture in Picture and every-frame scripts.
    static let videoPlatformIDs: Set<String> = [
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
        isVideoFullscreen = false
        retryTask?.cancel()
        retryTask = nil
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
        observations.forEach { $0.invalidate() }
        observations.removeAll()
    }

    /// Closing keeps the page for an instant reopen: playback stops as it would on close, but
    /// the page stays loaded in the background.
    func park() {
        isVideoFullscreen = false
        webView.evaluateJavaScript("""
        document.querySelectorAll('video, audio').forEach(function (media) { media.pause(); });
        """)
        webView.setAllMediaPlaybackSuspended(true, completionHandler: nil)
    }

    /// Reopening a parked page lets it play again; nothing starts by itself.
    func unpark() {
        webView.setAllMediaPlaybackSuspended(false, completionHandler: nil)
    }

    func goBack() {
        if webView.canGoBack { webView.goBack() } else { loadHome() }
    }

    /// Whether the page is a music player with next and previous songs.
    var hasTrackControls: Bool { TrackButtons.forPlatform(platform.id) != nil }

    /// The mini player's Next and Previous buttons; the same actions as the lock screen's.
    func nextTrack() { runTrackAction("nexttrack") }
    func previousTrack() { runTrackAction("previoustrack") }

    private func runTrackAction(_ action: String) {
        webView.evaluateJavaScript("window.__quietfeedTrack && window.__quietfeedTrack('\(action)');")
    }

    /// Plays or pauses the page's video. The mini-player's button, since the page's own
    /// controls are too small to use there. Music players use their own play button instead,
    /// since Spotify's audio isn't on the page.
    func togglePlayback() {
        if hasTrackControls { return runTrackAction("playpause") }
        webView.evaluateJavaScript("""
        (function () {
          var media = document.querySelector('video');
          if (!media) return;
          if (media.paused) { media.play().catch(function () {}); } else { media.pause(); }
        })();
        """)
    }

    /// Leaving QuietFeed with a video playing moves it into the system's floating Picture in
    /// Picture window, so only the video carries on over other apps, on every platform. It has
    /// to start while the app is still active (iOS refuses once it's in the background), and
    /// scripts the app runs count as a user gesture, which the request needs. Music without a
    /// picture (a YouTube Music song, Spotify) has no video track and keeps playing as audio.
    /// Sites that turn Picture in Picture off are allowed it again for this video.
    func enterPictureInPictureIfPlaying() {
        webView.evaluateJavaScript("""
        (function () {
          var videos = document.querySelectorAll('video');
          var seen = [];
          for (var i = 0; i < videos.length; i++) {
            var video = videos[i];
            seen.push([video.paused, video.ended, video.readyState, video.videoWidth].join('/'));
            if (video.paused || video.ended || video.readyState < 2 || !video.videoWidth) continue;
            video.removeAttribute('disablepictureinpicture');
            video.disablePictureInPicture = false;
            var supports = !!(video.webkitSupportsPresentationMode && video.webkitSupportsPresentationMode('picture-in-picture'));
            if (supports) {
              video.webkitSetPresentationMode('picture-in-picture');
            } else if (video.requestPictureInPicture) {
              video.requestPictureInPicture().catch(function (e) {
                window.webkit.messageHandlers.stillfeed.postMessage({ type: 'debug', message: 'pip rejected ' + e });
              });
            }
            return 'requested supports=' + supports + ' mode=' + video.webkitPresentationMode;
          }
          return 'no playing video: ' + seen.join(' ');
        })();
        """) { result, error in
            #if DEBUG
            print("[QF-PIP]", result ?? "nil", error.map { "\($0)" } ?? "")
            #endif
        }
    }

    /// The second route into Picture in Picture: each video that starts playing is marked as
    /// allowed to float on its own when the app leaves the screen (WebKit's auto Picture in
    /// Picture), and any site switch that turns Picture in Picture off is undone.
    private static let allowPictureInPictureSource = """
    (function () {
      document.addEventListener('play', function (event) {
        var video = event.target;
        if (!video || video.tagName !== 'VIDEO') return;
        video.removeAttribute('disablepictureinpicture');
        video.disablePictureInPicture = false;
        video.setAttribute('autopictureinpicture', '');
        try { video.autoPictureInPicture = true; } catch (e) { /* not supported here */ }
      }, true);
    })();
    """

    /// Back in QuietFeed, the video returns from the floating window to the page and keeps playing.
    func exitPictureInPicture() {
        webView.evaluateJavaScript("""
        (function () {
          document.querySelectorAll('video').forEach(function (video) {
            if (video.webkitPresentationMode === 'picture-in-picture') video.webkitSetPresentationMode('inline');
          });
          if (document.pictureInPictureElement && document.exitPictureInPicture) {
            document.exitPictureInPicture().catch(function () {});
          }
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
        if SiteBarSlot.forPlatform(platform.id) != nil {
            let enabled = Self.hidesHeader(rules)
            webView.evaluateJavaScript("window.__quietfeedNavAnchor && window.__quietfeedNavAnchor.setEnabled(\(enabled));")
            if !enabled { siteNavAnchor = .missing }
        }
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
        if let slot = SiteBarSlot.forPlatform(platform.id) {
            controller.addUserScript(WKUserScript(
                source: Self.navAnchorSource(slot, enabled: Self.hidesHeader(rules)),
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
        #if os(iOS)
        controller.addUserScript(WKUserScript(
            source: Self.allowPictureInPictureSource,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: !Self.videoPlatformIDs.contains(platform.id)
        ))
        #endif
        if let buttons = TrackButtons.forPlatform(platform.id) {
            controller.addUserScript(WKUserScript(
                source: Self.trackControlsSource(buttons),
                injectionTime: .atDocumentStart,
                forMainFrameOnly: true
            ))
        }
        if platform.id == "youtube_music" {
            controller.addUserScript(WKUserScript(
                source: Self.releaseHiddenModalSource,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: true
            ))
            #if DEBUG
            controller.addUserScript(WKUserScript(
                source: Self.tapDiagnosticsSource,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: true
            ))
            #endif
        }
        #if DEBUG
        if platform.id == "spotify" {
            controller.addUserScript(WKUserScript(
                source: Self.spotifyAdDiagnosticsSource,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: true
            ))
        }
        #endif
    }

    #if DEBUG
    /// Temporary: logs what Spotify shows while something plays (page title, lock-screen details,
    /// the now-playing bar's text and links, the playing media, and whether the engine muted it),
    /// whenever any of it changes, to see what a real ad or promo looks like. Prints as [QF-AD].
    private static let spotifyAdDiagnosticsSource = """
    (function () {
      var last = '';
      setInterval(function () {
        var meta = navigator.mediaSession && navigator.mediaSession.metadata;
        var widget = document.querySelector('[data-testid="now-playing-widget"]');
        var links = widget ? Array.prototype.map.call(widget.querySelectorAll('a[href]'), function (a) {
          return (a.getAttribute('data-testid') || 'a') + '=' + a.getAttribute('href');
        }) : [];
        var testids = widget ? Array.prototype.map.call(widget.querySelectorAll('[data-testid]'), function (el) {
          return el.getAttribute('data-testid');
        }) : [];
        var media = Array.prototype.map.call(document.querySelectorAll('video, audio'), function (m) {
          return m.tagName + (m.paused ? ' paused' : ' playing') + (m.muted ? ' muted' : '') +
            ' dur=' + Math.round(m.duration || 0) + ' src=' + String(m.currentSrc || m.src || '').slice(0, 60);
        });
        var report = 'title=' + document.title +
          ' | meta=' + (meta ? [meta.title, meta.artist, meta.album].join(' / ') : 'none') +
          ' | bar=' + (widget ? (widget.textContent || '').trim().slice(0, 120) : 'none') +
          ' | links=' + links.join(', ') +
          ' | testids=' + testids.join(',') +
          ' | domMedia=' + media.join('; ');
        if (report === last) return;
        last = report;
        try { window.webkit.messageHandlers.stillfeed.postMessage({ type: 'debug', message: '[QF-AD] ' + report.slice(0, 1500) }); } catch (e) {}
      }, 1000);
    })();
    """

    /// Temporary: logs what each tap lands on, pop-ups that appear, and media events, to find
    /// why taps on YouTube Music songs don't play on a real iPhone.
    private static let tapDiagnosticsSource = """
    (function () {
      function log(msg) {
        try { window.webkit.messageHandlers.stillfeed.postMessage({ type: 'debug', message: String(msg).slice(0, 600) }); } catch (e) {}
      }
      function describe(el) {
        var parts = [];
        for (var i = 0; el && i < 6; i++, el = el.parentElement) {
          var cs = getComputedStyle(el);
          parts.push(el.tagName.toLowerCase() + (el.id ? '#' + el.id : '') +
            (el.className && typeof el.className === 'string' ? '.' + el.className.trim().split(/\\s+/).slice(0, 2).join('.') : '') +
            (el.hasAttribute('data-stillfeed-hidden') ? '[QF-HIDDEN]' : '') +
            (cs.position === 'fixed' ? '[fixed]' : '') + (cs.pointerEvents === 'none' ? '[pe:none]' : ''));
        }
        return parts.join(' < ');
      }
      ['touchstart', 'click'].forEach(function (type) {
        document.addEventListener(type, function (e) {
          var t = e.touches && e.touches[0];
          var x = t ? t.clientX : e.clientX, y = t ? t.clientY : e.clientY;
          log(type + ' @' + Math.round(x) + ',' + Math.round(y) + ' target=' + describe(e.target) +
              ' | atPoint=' + describe(document.elementFromPoint(x, y)) + ' defaultPrevented=' + e.defaultPrevented +
              ' | modal: dialog[open]=' + document.querySelectorAll('dialog[open]').length +
              ' inert=' + Array.prototype.map.call(document.querySelectorAll('[inert]'), function (n) { return n.tagName.toLowerCase(); }).join(',') +
              ' qfHidden=' + Array.prototype.map.call(document.querySelectorAll('[data-stillfeed-hidden]'), function (n) { return n.tagName.toLowerCase(); }).join(',') +
              ' bodyPE=' + (document.body ? getComputedStyle(document.body).pointerEvents : '?'));
        }, true);
      });
      ['play', 'playing', 'pause', 'error', 'stalled'].forEach(function (type) {
        document.addEventListener(type, function (e) {
          var m = e.target;
          log('media ' + type + ' src=' + String(m.currentSrc || '').slice(0, 60) + ' err=' + (m.error ? m.error.code + ' ' + m.error.message : ''));
        }, true);
      });
      window.addEventListener('error', function (e) { log('js error ' + e.message); });
      window.addEventListener('unhandledrejection', function (e) { log('rejection ' + (e.reason && e.reason.message || e.reason)); });
      new MutationObserver(function (records) {
        records.forEach(function (r) {
          r.addedNodes.forEach(function (n) {
            if (n.nodeType !== 1) return;
            var tag = n.tagName.toLowerCase();
            if (/dialog|popup|sheet|backdrop|overlay|upsell|promo|toast/.test(tag) || n.getAttribute('role') === 'dialog') {
              log('added ' + tag + ' text="' + (n.textContent || '').trim().replace(/\\s+/g, ' ').slice(0, 160) + '"');
            }
          });
        });
      }).observe(document.documentElement, { childList: true, subtree: true });
      log('diagnostics ready ' + navigator.userAgent);
    })();
    """
    #endif

    /// The lock screen and Control Center build their buttons from the page's media session:
    /// seek handlers give ±10 second buttons, track handlers give next and previous song.
    /// For music services this drops the seek handlers and makes sure there are track handlers,
    /// using the site's own if it registers them, or pressing its Next/Previous buttons if not.
    /// It also gives QuietFeed's mini player the same actions (`window.__quietfeedTrack`), since
    /// the site's player bar may leave Next out on a narrow screen and Spotify's audio isn't on
    /// the page for QuietFeed to reach directly.
    private static func trackControlsSource(_ buttons: TrackButtons) -> String {
        """
        (function () {
          var buttons = {
            nexttrack: \(jsonLiteral(buttons.next)),
            previoustrack: \(jsonLiteral(buttons.previous)),
            playpause: \(jsonLiteral(buttons.playPause))
          };
          var pageHandlers = {};
          function press(selectors) {
            for (var i = 0; i < selectors.length; i++) {
              var button = document.querySelector(selectors[i]);
              if (button && !button.disabled) { button.click(); return true; }
            }
            return false;
          }
          function playing() {
            var media = document.querySelectorAll('video, audio');
            for (var i = 0; i < media.length; i++) if (!media[i].paused) return media[i];
            return null;
          }
          // The site's own handler first (it knows its queue), else its button.
          window.__quietfeedTrack = function (action) {
            if (action === 'playpause') {
              if (press(buttons.playpause)) return;
              var media = playing();
              var handler = pageHandlers[media ? 'pause' : 'play'];
              if (handler) { handler({ action: media ? 'pause' : 'play' }); return; }
              if (media) { media.pause(); return; }
              var first = document.querySelector('video, audio');
              if (first) first.play().catch(function () {});
              return;
            }
            if (pageHandlers[action]) { pageHandlers[action]({ action: action }); return; }
            press(buttons[action] || []);
          };

          var session = navigator.mediaSession;
          if (!session || typeof session.setActionHandler !== 'function') return;
          var original = session.setActionHandler.bind(session);
          function set(action, handler) {
            try { original(action, handler); } catch (e) { /* action not supported here */ }
          }

          session.setActionHandler = function (action, handler) {
            if (action === 'seekforward' || action === 'seekbackward') return set(action, null);
            pageHandlers[action] = handler || null;
            return set(action, handler);
          };

          function useTrackControls() {
            set('seekforward', null);
            set('seekbackward', null);
            ['nexttrack', 'previoustrack'].forEach(function (action) {
              if (!pageHandlers[action]) set(action, function () { press(buttons[action]); });
            });
          }

          // Media "play" events don't bubble, so listen in the capture phase. Each new song reapplies it.
          document.addEventListener('play', useTrackControls, true);
          useTrackControls();
        })();
        """
    }

    /// While a pop-up is open, YouTube Music makes the rest of the page `inert`, which ignores
    /// every tap (scrolling still works, as it's native). If a filter hides that pop-up, nothing
    /// is left to close it and the page stays dead. This lifts `inert` once no pop-up is visible.
    private static let releaseHiddenModalSource = """
    (function () {
      var timer = null;
      function anyVisiblePopup() {
        var popups = document.querySelectorAll('tp-yt-paper-dialog, tp-yt-iron-dropdown, ytmusic-popup-container [role="dialog"], dialog[open]');
        for (var i = 0; i < popups.length; i++) {
          var box = popups[i].getBoundingClientRect();
          if (box.width > 0 && box.height > 0 && getComputedStyle(popups[i]).visibility !== 'hidden') return true;
        }
        return false;
      }
      function check() {
        timer = null;
        var blocked = document.querySelectorAll('ytmusic-app-layout[inert], ytmusic-player-bar[inert], ytmusic-app [inert]');
        if (!blocked.length || anyVisiblePopup()) return;
        for (var i = 0; i < blocked.length; i++) blocked[i].removeAttribute('inert');
      }
      // Wait a moment so a pop-up that's still opening counts as visible.
      function schedule() { if (timer === null) timer = setTimeout(check, 400); }
      new MutationObserver(schedule).observe(document.documentElement, {
        subtree: true, childList: true, attributes: true, attributeFilter: ['inert', 'style', 'hidden']
      });
      document.addEventListener('touchstart', check, true);
    })();
    """

    private static func hidesHeader(_ rules: [FilterRule]) -> Bool {
        rules.contains { $0.key == "hide_header" }
    }

    /// YouTube Music's top bar has no free space when signed out (search sits mid-bar), so
    /// QuietFeed's Back and Close take the place of the site's logo, which only links to Home
    /// (as the bottom Home tab does). The logo is hidden but keeps a slot wide enough for the two
    /// buttons, and the page reports where that slot is, so the buttons line up with the site's
    /// icons and leave with the bar when it scrolls away. "missing" means the bar isn't there
    /// (yet, or the site changed), and QuietFeed falls back to its own strip of controls.
    /// Every platform's own top bar shows its logo, which only links to the site's home. QuietFeed's
    /// Back and Close take that place: the logo is hidden but keeps a slot wide enough for the two
    /// buttons, and the page reports where the slot is, so the buttons line up with the site's
    /// icons and leave with the bar when it scrolls away. "missing" means no logo was found at the
    /// top of the page (yet, or the site changed), and QuietFeed falls back to its own strip.
    private static func navAnchorSource(_ slot: SiteBarSlot, enabled: Bool) -> String {
        """
        (function () {
          if (window.__quietfeedNavAnchor) return;
          var STYLE_ID = 'quietfeed-nav-anchor';
          var MARK = 'data-quietfeed-slot';
          var LOGOS = \(jsonLiteral(slot.logo));
          var BAR = \(jsonLiteral(slot.bar ?? ""));
          var enabled = \(enabled);
          var last = null, frame = null, followUntil = 0;

          function setStyle() {
            var style = document.getElementById(STYLE_ID);
            if (!enabled) {
              if (style) style.remove();
              document.querySelectorAll('[' + MARK + ']').forEach(function (el) { el.removeAttribute(MARK); });
              return;
            }
            if (style || !document.documentElement) return;
            style = document.createElement('style');
            style.id = STYLE_ID;
            // YouTube Music's 1px divider sits below the screen edge, so it isn't slid away with
            // the bar; the app has none, so it's simply removed.
            style.textContent = '[' + MARK + ']{visibility:hidden!important;min-width:\(Int(SiteNavAnchor.slotWidth))px!important;flex-shrink:0!important;}' +
              '#nav-bar-divider{display:none!important;}';
            (document.head || document.documentElement).appendChild(style);
          }
          function post(message) {
            var key = JSON.stringify(message);
            if (key === last) return;
            last = key;
            window.webkit.messageHandlers.stillfeed.postMessage(message);
          }
          // A logo only counts when it's drawn and sits inside a short bar at the top of the page,
          // so an invisible match or a logo in a footer never takes the controls away.
          function slotFor(logo) {
            var bar = findBar(logo);
            if (!bar) return null;
            var box = bar.getBoundingClientRect();
            var slot = logo.getBoundingClientRect();
            if (box.height === 0 || box.height > 140 || box.top > 120) return null;
            if (slot.width === 0 || slot.height === 0) return null;
            if (slot.top < box.top - 2 || slot.bottom > box.bottom + 2) return null;
            // Something drawn over the bar (Spotify's full-screen player, a sheet) has its own
            // controls there; the buttons would cover them. The hidden logo itself can't be hit,
            // so what's normally under its middle is the bar. Off screen counts as not covered.
            var x = slot.left + slot.width / 2, y = slot.top + slot.height / 2;
            if (y >= 0 && y < window.innerHeight) {
              var hit = document.elementFromPoint(x, y);
              if (hit && !bar.contains(hit) && !hit.contains(bar)) return null;
            }
            return { logo: logo, slot: slot, box: box };
          }
          // The marked logo while it still counts, else the first match that does, in the
          // selectors' priority order. The logo is the link around a logo image, if there is one.
          function findSlot() {
            var marked = document.querySelector('[' + MARK + ']');
            if (marked) {
              var kept = slotFor(marked);
              if (kept) return kept;
              // A bar that scrolls with the page (Netflix's) has simply gone up out of view.
              if (marked.isConnected && marked.getBoundingClientRect().bottom <= 0) return { offscreen: true };
              marked.removeAttribute(MARK);
            }
            for (var i = 0; i < LOGOS.length; i++) {
              var matches = [];
              try { matches = document.querySelectorAll(LOGOS[i]); } catch (e) { /* unsupported selector */ }
              for (var j = 0; j < matches.length; j++) {
                var logo = matches[j].closest('a,button') || matches[j];
                var found = slotFor(logo);
                if (found) {
                  logo.setAttribute(MARK, '');
                  // Measure again: keeping the slot wide can move the logo.
                  return slotFor(logo) || found;
                }
              }
            }
            return null;
          }
          // The site's configured bar, else the pinned (fixed or sticky) bar the logo sits in,
          // else the widest short row around it.
          function findBar(logo) {
            if (BAR) return logo.closest(BAR);
            var row = null;
            for (var el = logo.parentElement; el && el !== document.body; el = el.parentElement) {
              var position = getComputedStyle(el).position;
              if (position === 'fixed' || position === 'sticky') return el;
              var box = el.getBoundingClientRect();
              if (box.height > 120) break;
              if (box.width >= window.innerWidth * 0.6) row = el;
            }
            return row;
          }
          function report() {
            frame = null;
            setStyle();
            if (!enabled) return;
            var found = findSlot();
            if (!found) {
              post({ type: 'navAnchor', state: 'missing' });
            } else {
              var slot = found.slot, box = found.box;
              // Off screen only once the bar has moved up and mostly out of view.
              if (found.offscreen || (box.top < 0 && box.bottom < box.height / 2)) {
                post({ type: 'navAnchor', state: 'offscreen' });
              } else {
                // Centre on the logo's drawn image, where the person sees the logo. A link can
                // be taller than its image (Netflix's includes screen-reader text below it).
                var image = found.logo.matches('svg,img') ? found.logo : found.logo.querySelector('svg,img');
                var art = image && image.getBoundingClientRect();
                var middle = art && art.height > 0 ? art.top + art.height / 2 : box.top + box.height / 2;
                post({ type: 'navAnchor', state: 'visible',
                       x: Math.round(slot.left), y: Math.round(middle - box.height / 2),
                       width: Math.round(slot.width), height: Math.round(box.height) });
              }
            }
            if (Date.now() < followUntil) schedule();
          }
          function schedule() { if (frame === null) frame = requestAnimationFrame(report); }
          // Follow the bar frame by frame while it slides (FilterEngine moves it over 0.25s).
          function follow() { followUntil = Date.now() + 400; schedule(); }
          window.addEventListener('scroll', follow, true);
          window.addEventListener('resize', schedule);
          document.addEventListener('transitionrun', follow, true);
          document.addEventListener('transitionend', schedule, true);
          // A slow check catches pages the site builds or swaps without scrolling.
          setInterval(schedule, 500);
          // QuietFeed forgets the slot whenever a page commits, including one restored from the
          // back-forward cache, where this script keeps running. Send it again then, even if
          // it hasn't moved, or the app would wait for a change that never comes.
          function resend() { last = null; schedule(); }
          window.addEventListener('pageshow', resend);
          window.addEventListener('popstate', resend);
          window.__quietfeedNavAnchor = {
            setEnabled: function (value) { enabled = !!value; last = null; setStyle(); schedule(); },
            resend: resend
          };
          schedule();
        })();
        """
    }

    /// A string or list of strings as a JavaScript literal.
    private static func jsonLiteral(_ value: some Encodable) -> String {
        (try? JSONEncoder().encode(value)).map { String(decoding: $0, as: UTF8.self) } ?? "null"
    }

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

    /// Largest count one filter pass can report. Any frame on the page can post to the
    /// message handler, so a page can't inflate the weekly totals past this.
    private static let maxHiddenPerMessage = 500

    fileprivate func handleMessage(_ message: WKScriptMessage) {
        guard let body = message.body as? [String: Any], let type = body["type"] as? String else { return }
        let host = message.frameInfo.securityOrigin.host
        guard navGuard.isTrustedMessageOrigin(host: host, isMainFrame: message.frameInfo.isMainFrame) else {
            return
        }
        switch type {
        case "hidden":
            guard let count = body["count"] as? NSNumber else { return }
            insights.recordHidden(min(max(count.intValue, 0), Self.maxHiddenPerMessage))
        case "videoFullscreen":
            isVideoFullscreen = (body["active"] as? Bool) ?? false
        case "navAnchor":
            guard SiteBarSlot.forPlatform(platform.id) != nil else { return }
            siteNavAnchor = SiteNavAnchor(message: body)
        #if DEBUG
        case "debug":
            print("[QF-TAP]", body["message"] as? String ?? "")
        #endif
        default:
            return
        }
    }

    private func fail(_ error: Error) {
        #if canImport(UIKit)
        refreshControl?.endRefreshing()
        #endif
        let nsError = error as NSError
        endLoadInterval("failed")
        switch LoadFailurePolicy.outcome(domain: nsError.domain, code: nsError.code, attempt: failedAttempts) {
        case .ignore:
            return
        case .offline:
            state = .offline
        case .retry(let delay):
            failedAttempts += 1
            retryTask?.cancel()
            retryTask = Task { [weak self] in
                try? await Task.sleep(for: delay)
                guard !Task.isCancelled, let self else { return }
                self.reload()
            }
        case .fail:
            state = .error("Check your connection and try again.")
        }
    }

    /// Reloads a page that couldn't load because the device was offline, once it's back online.
    func connectivityChanged(isOnline: Bool) {
        guard isOnline, state == .offline else { return }
        failedAttempts = 0
        reload()
    }
}

extension WebModel: WKNavigationDelegate {
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
        guard let url = navigationAction.request.url else { return .cancel }
        let isMainFrame = navigationAction.targetFrame?.isMainFrame ?? true
        let decision = navGuard.decide(url: url, isMainFrame: isMainFrame)
        if isMainFrame, navigationAction.navigationType == .linkActivated, decision != .cancel {
            lastLinkTap = .now
        }
        switch decision {
        case .allow:
            return .allow
        case .redirect(let destination):
            webView.load(URLRequest(url: destination))
            return .cancel
        case .external(let outside):
            // Only leave the app for a link the person tapped. A page's own script or a timed
            // redirect could otherwise bounce them out (to the App Store, say) without asking.
            // A few seconds of grace covers link shims like l.instagram.com, which redirect
            // to the real site after the tap.
            guard let tap = lastLinkTap, Date.now.timeIntervalSince(tap) < Self.externalLinkGrace else {
                return .cancel
            }
            lastLinkTap = nil
            openExternally(outside)
            return .cancel
        case .cancel:
            return .cancel
        }
    }

    /// A new document replaces the page's scripts, including any in-window full screen, so
    /// the app's bar and Close button must come back rather than stay hidden for good.
    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        isVideoFullscreen = false
        siteNavAnchor = .missing
        // A page restored from the back-forward cache keeps its scripts; ask it to report again.
        webView.evaluateJavaScript("window.__quietfeedNavAnchor && window.__quietfeedNavAnchor.resend();")
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        state = .loading(progress: webView.estimatedProgress)
        endLoadInterval("superseded")
        loadInterval = Self.signposter.beginInterval("Page load", id: Self.signposter.makeSignpostID(), "\(self.platform.id, privacy: .public)")
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        state = .loaded
        endLoadInterval("finished")
        failedAttempts = 0
        retryTask?.cancel()
        retryTask = nil
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
        isVideoFullscreen = false
        // Reload after a crash, but not forever: a page that keeps taking its process down
        // (out of memory, say) would otherwise reload, crash and drain the battery in a loop.
        let now = Date.now
        processTerminations = processTerminations.filter { now.timeIntervalSince($0) < Self.crashWindow } + [now]
        if processTerminations.count > Self.maxCrashReloads {
            state = .error("This page keeps stopping. Reload to try again.")
            return
        }
        reload()
    }
}

extension WebModel {
    /// Hands a page outside the platform to Safari or the app that owns it.
    private func openExternally(_ url: URL) {
        #if canImport(UIKit)
        UIApplication.shared.open(url)
        #elseif canImport(AppKit)
        NSWorkspace.shared.open(url)
        #endif
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
                // Scripted pop-ups must not be able to move the person into another app.
                if navigationAction.navigationType == .linkActivated {
                    openExternally(outside)
                }
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
        target?.handleMessage(message)
    }
}

/// A music site's own Next, Previous and Play/Pause buttons, pressed when the site hasn't given
/// the lock screen its own track actions. Several selectors each, in priority order.
struct TrackButtons {
    let next: [String]
    let previous: [String]
    let playPause: [String]

    static func forPlatform(_ id: String) -> TrackButtons? {
        switch id {
        case "youtube_music":
            return TrackButtons(
                next: [".next-button", "button[aria-label=\"Next\"]", "button[aria-label=\"Next song\"]"],
                previous: [".previous-button", "button[aria-label=\"Previous\"]", "button[aria-label=\"Previous song\"]"],
                playPause: ["#play-pause-button", "ytmusic-player-bar .play-pause-button"])
        case "spotify":
            return TrackButtons(
                next: ["[data-testid=\"control-button-skip-forward\"]", "button[aria-label=\"Next\"]"],
                previous: ["[data-testid=\"control-button-skip-back\"]", "button[aria-label=\"Previous\"]"],
                playPause: ["[data-testid=\"control-button-playpause\"]",
                            "[data-testid=\"now-playing-bar\"] button[aria-label=\"Play\"]",
                            "[data-testid=\"now-playing-bar\"] button[aria-label=\"Pause\"]"])
        default:
            return nil
        }
    }
}

/// How to find each site's logo in its top bar, the place QuietFeed's Back and Close take.
/// Several selectors per site, so a small redesign still matches one of them.
struct SiteBarSlot {
    /// Selectors for the logo (or the logo's image; the link around it is used), tried in order,
    /// so a broad last resort only counts when the precise ones miss.
    let logo: [String]
    /// The bar the logo sits in, when the site names it; otherwise the logo's pinned ancestor.
    var bar: String? = nil

    static func forPlatform(_ id: String) -> SiteBarSlot? {
        switch id {
        case "youtube_music":
            return SiteBarSlot(
                logo: ["ytmusic-nav-bar a.ytmusic-logo", "ytmusic-nav-bar a[title=\"Home\"]", "ytmusic-nav-bar a[aria-label=\"Home\"]"],
                bar: "ytmusic-nav-bar")
        case "youtube":
            return SiteBarSlot(
                logo: ["ytm-mobile-topbar-renderer ytm-home-logo", "ytm-mobile-topbar-renderer #home-icon",
                       "header.mobile-topbar-header a[aria-label*=\"YouTube\"]"],
                bar: "ytm-mobile-topbar-renderer, header.mobile-topbar-header")
        case "instagram":
            // Signed out, the wordmark sits mid-page rather than in a bar, so this falls back.
            return SiteBarSlot(logo: ["svg[aria-label=\"Instagram\"]", "a[href=\"/\"] i[aria-label=\"Instagram\"]"])
        case "netflix":
            // The logo is an unlabelled image beside screen-reader text, inside the header's home link.
            return SiteBarSlot(logo: ["[data-uia*=\"logo\" i]", "a.logo", "a[aria-label=\"Netflix\"]",
                                      "header a[href=\"/\"]", "[role=\"banner\"] a[href=\"/\"]",
                                      "header a[href^=\"/\"]:has(svg)", "[role=\"banner\"] a[href^=\"/\"]:has(svg)",
                                      "header svg"])
        case "amazon_prime":
            // The logo is the navigation bar's link named "Home", named by its image rather than
            // a label, so it's also found by where it links.
            return SiteBarSlot(logo: ["[role=\"banner\"] a[aria-label=\"Home\"]", "header a[aria-label=\"Home\"]",
                                      "nav a[aria-label=\"Home\"]", "a[data-testid*=\"logo\" i]",
                                      "[role=\"banner\"] nav a[href*=\"storefront\"]:has(svg, img)",
                                      "header nav a[href*=\"storefront\"]:has(svg, img)",
                                      "[role=\"banner\"] a[href*=\"nb_logo\"]", "header a[href*=\"nb_logo\"]",
                                      "[role=\"banner\"] nav > a:has(svg, img)", "header nav > a:has(svg, img)",
                                      "a[aria-label=\"Prime Video\"]"])
        case "spotify":
            return SiteBarSlot(logo: ["a[aria-label=\"Spotify\"]", "svg[aria-label=\"Spotify\"]"])
        default:
            return nil
        }
    }
}

/// Where a site's own top bar has room for QuietFeed's controls, as reported by the page.
enum SiteNavAnchor: Equatable {
    /// The bar isn't on the page; QuietFeed shows its own controls instead.
    case missing
    /// The bar has scrolled out of view, so the controls go with it.
    case offscreen
    /// The slot's position in the web view, in points: the logo's x-range, the bar's height.
    case visible(CGRect)

    /// Room the page keeps free for Back and Close, two 44pt tap targets.
    static let slotWidth: CGFloat = 88

    init(message body: [String: Any]) {
        switch body["state"] as? String {
        case "offscreen":
            self = .offscreen
        case "visible":
            let value = { (key: String) in CGFloat((body[key] as? NSNumber)?.doubleValue ?? 0) }
            let rect = CGRect(x: value("x"), y: value("y"), width: value("width"), height: value("height"))
            // Ignore anything that couldn't be a top bar, so a page can't place the controls oddly.
            let plausible = rect.height > 0 && rect.height < 200 && rect.minX >= 0 && rect.minX < 400
                && rect.minY > -200 && rect.minY < 200
            self = plausible ? .visible(rect) : .missing
        default:
            self = .missing
        }
    }
}
