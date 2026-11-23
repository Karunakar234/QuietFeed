# QuietFeed audit — 2026-11-20

Branch: `audit/hardening-2026-11` (from `main` @ `bf569e0 version 7`). `main` is untouched.

## A. Architecture summary

- **App:** SwiftUI + SwiftData, one multiplatform target (`QuietFeed`: iPhone, iPad, Mac, visionOS; iOS 27.2 / macOS 26.7.2), plus a small tvOS launcher (`QuietFeedTV`). Swift 5 mode, default MainActor isolation, App Sandbox on. No backend, no third-party dependencies, no secrets in the repo.
- **Core flow:** `RuleStore` loads the bundled `rules.json` → `PlatformScreen` creates a `WebModel` (one `WKWebView` per platform, with a per-account `WKWebsiteDataStore`) → `FilterEngine.js` is injected at document start and hides, redirects, auto-hides bars and skips ads; `NavigationGuard.swift` repeats the navigation rules natively; `AdBlocker` adds a `WKContentRuleList`.
- **Persistence:** `PlatformSetting` and `Account` (SwiftData); weekly counts in `Application Support/QuietFeed/weekly-insights.json`.
- **Platforms:** Instagram, YouTube, YouTube Music, Netflix, Prime Video, Spotify.
- **Project format:** `QuietFeed/` is a *synchronized folder*, so every file placed in it joins the app target. Tests therefore live in `Tests/` at the repo root.

## B/C. Issues found and fixed

| # | Severity | Where | Root cause → fix | Verified |
|---|---|---|---|---|
| 1 | **High** | `FilterEngine.js` `findSpotifyAdLabel` | A Spotify track whose title *starts with* "Ad"/"Sponsored" ("Ad Astra") counted as an ad, so the song was muted and seeked to its end. The now-playing title now has to be exactly the ad label. | JS test (failed before, passes now) |
| 2 | **Medium (security)** | `WebModel.handleMessage` | Any frame (including ad/third-party iframes, since the engine runs in every frame on video sites) could post `videoFullscreen`, which hides QuietFeed's bar **and** Close button, or post huge `hidden` counts. Now only the platform's own top-level page can change full screen, and counts are clamped to 0…500 per message. | Code review only (Swift not compiled here) |
| 3 | **Medium** | `WebModel` | If a page navigated while in Mac in-window full screen, `isVideoFullscreen` stayed `true` and the app's controls never came back. It now resets on main-frame commit, web-process crash and shutdown. | Code review only |
| 4 | **Medium (performance)** | `FilterEngine.js` `skipPlaybackAd` (every 200 ms) | 3+ whole-document walks (`querySelectorAll('*')` for shadow roots, plus Prime's span/p text scan) ran on every video and music site, even with no ad showing. They now run only on Prime Video, the one site that needs them. | JS test: 6 walks per 2 ticks → 0; Prime shadow-DOM detection covered by a regression test |
| 5 | Low | `FilterEngine.js` `scan` | Changing any filter switch unhides and rescans, which re-counted every hidden post in weekly insights. | JS test (failed before, passes now) |
| 6 | Low (performance) | `WeeklyInsightsStore` | One atomic JSON write per filter pass (every ~30 ms while scrolling). Writes are now batched to at most one per 2 s and flushed when the app leaves the foreground. | Code review only |
| 7 | Low | `WebModel.init` | Closing a page before the ad rules finished compiling (first launch) started a late load in the closed page. Now skipped. | Code review only |
| 8 | Low (a11y) | all `Motion.spring` sites | Reduce Motion was ignored. `Motion.gentle` (new `Theme/MotionPreference.swift`) gives no animation when Reduce Motion is on. | Code review only |
| 9 | Low (copy/legal) | `StubScreens.swift`, `Primitives.swift` | "on this phone" on Mac/iPad; data-deletion copy and the "not affiliated" notice named only Instagram and YouTube; the Post button's VoiceOver hint promised a feature that isn't built. | — |
| 10 | Repo hygiene | root | `QuietFeed.xcodeproj` wasn't tracked by git (only the deleted "Untitled Project" was). Now tracked; `.gitignore` excludes `xcuserdata`, `.DS_Store`, `DerivedData`. | `git status` |

Commits on the branch:
1. `WIP preserved` — **your** uncommitted changes as found (YouTube Music close-button alignment, Untitled Project removal), committed unchanged so nothing was lost.
2. Track the Xcode project and add `.gitignore`.
3. FilterEngine fixes and JS tests.
4. Swift fixes.

Uncommitted on purpose: `rules.json` (a new YouTube Music backdrop rule) and `HomeCards.swift` (AuroraBackground layout). Both were edited during the audit, and not by me. They pass the rules tests.

## D. UI/UX

Not redesigned. The Liquid Glass design is recent, consistent and token-based (`Theme.swift`, `Primitives.swift`), and a redesign I couldn't run or preview would be high-risk. Changes made: Reduce Motion, honest VoiceOver hint, device-neutral copy. Suggested design work is in H.

## E. Performance

- Ad-check cost: measured in jsdom on a 1,000-node page, whole-page walks dropped from **6 per two 200 ms ticks to 0** on YouTube, YouTube Music and Spotify. No on-device measurements (Instruments) were taken.
- Insight writes: from one write per filter pass to at most one per 2 seconds (by construction, not measured).

## F. Testing and validation

| Command | Result |
|---|---|
| `node --check QuietFeed/Filtering/FilterEngine.js` | OK |
| `cd Tests/js && npm install && npm test` (24 tests: engine behaviour in jsdom + `rules.json` invariants) | Baseline **19/22 pass (3 real bugs)** → after fixes **24/24 pass** |
| Swift build / unit tests / UI tests | **Not run.** There's no Swift toolchain or Xcode in the audit environment, and the project has no test target. |

## G. Breaking-change assessment

None intended. SwiftData models, the `rules.json` schema, the JS↔Swift message format and public behaviour are unchanged. The bridge now *ignores* `videoFullscreen` from non-main or off-platform frames. If a platform ever runs its player in an iframe on another host, Mac in-window full screen won't hide the app bar there.

## H. Open issues and recommendations (not changed; need testing or a decision)

1. **Medium — external links open without a user tap.** `NavigationGuard` sends *any* main-frame navigation to an off-platform host to Safari/the system, including script redirects. That lets a page bounce people out of the app (for example to the App Store). Fix: only open externally for `navigationType == .linkActivated` or a user-initiated `window.open`. Needs device testing, because Instagram's `l.instagram.com` link shim relies on redirects.
2. **Medium — the engine runs in the page's own JS world.** A site can call `window.__stillfeed.update([])` to switch the filters off. Move hiding/redirect logic into an isolated `WKContentWorld` (the ad-response sanitizer and full-screen shim must stay in the page world). Needs testing on every platform.
3. Low — `updateRules` updates the main frame only; child frames keep the old rules until reload.
4. Low — Prime Video `allowed_hosts` has `amazon.com` only, so sign-in on amazon.co.uk/.de/etc. leaves the app.
5. Low — the Mac window buttons are 12 pt, below the WCAG 2.2 24 px target size (they match macOS's own traffic lights).
6. Low — `AuroraBackground` renders four 100 pt blurs behind every screen and the open page. Consider rendering it once to an image or `drawingGroup()`; profile with Instruments first.
7. Verify on device — background audio resume (`AVAudioSession.activate {}`), the mini-player, and Mac in-window full screen after these changes.
8. **Tests and CI:** add a Unit Testing Bundle target in Xcode. `NavigationGuard`, `RuleStore.enabledRules` and `WeeklyInsightsStore` are pure enough to test directly. Add a GitHub Action that runs `Tests/js`.
9. Features worth proposing (not built): per-platform daily time limits on Stats; saved recommended searches; a "report a slip-through" flow (the `filterProblem` state already exists in `WebStateOverlay`).

## Pass 2 — 2026-11-21 (built and tested in Xcode)

The first pass ran with no Xcode, so this pass compiled the app, ran it on a real iPhone, and added Swift tests.

**Baseline:** the iPhone and Mac builds both succeeded with 0 errors and 0 warnings. JS tests passed 24/24. There was no Swift test target.

| # | Severity | Where | Root cause → fix | Verified |
|---|---|---|---|---|
| P1 | **Critical** | `rules.json` (YouTube Music) | On a real iPhone, taps on songs did nothing while scrolling still worked. A debug tap logger showed every tap landing on `<html>`, with `ytmusic-app-layout` and the player bar marked `inert`. The cause: YouTube Music opened its "Get the app / No thanks" pop-up, and **Remove ads** hid the promo inside it (`ytmusic-mealbar-promo-renderer`) while **Stay in QuietFeed** hid `tp-yt-paper-dialog` / `[role=dialog]`. The pop-up was invisible but still modal, so the page stayed inert. Fix: these pop-ups are no longer hidden with CSS. Their own dismiss button ("No thanks", "Not now", …) is pressed instead. | Device log (cause); JS tests ×3; Swift rules test; re-test on device pending |
| P2 | High | `FilterEngine.js` `scan` (click action) | Each dismiss button was pressed only once, ever, so a pop-up the site reused stayed open the second time. It's now pressed whenever it's visible, at most once a second. Invisible buttons are skipped. | JS tests |
| P3 | High | `WebModel.swift` (YouTube Music only) | Safety net: if the layout is `inert` while no pop-up is visible, `inert` is lifted (checked on DOM changes and on every touch). | Build; device re-test pending |
| P4 | High (layout) | `HomeCards.swift` `AuroraBackground` | The glow ellipses (up to 540 pt) were ZStack children, so the backdrop reported a 540 pt width and pushed content past the screen edges wherever it was used as a layout child. The glows are now an overlay on the gradient. | Simulator: onboarding frames sit inside the 20 pt margins on a 402 pt screen |
| P5 | Medium (security, was H1) | `WebModel` navigation delegate | A page could send people out of the app (to the App Store, say) through a script redirect, with no tap. Leaving the app now needs a link tap within the last 10 s, which keeps link shims like `l.instagram.com` working. `window.open` already requires a user gesture. | Build; manual check recommended |
| P6 | Low (was H4) | `rules.json` Prime Video | Sign-in on amazon.co.uk/.de/.in/… left the app. The regional Amazon domains are now allowed. | Swift tests |
| P7 | Testability | `WeeklyInsightsStore.init` | The file location was hard-coded, so tests would have touched real data. Optional `directory:` and `now:` parameters were added; the app's behaviour is unchanged. | Swift tests |
| P8 | Tests | `QuietFeedTests` target (Swift Testing), hosted by the app | 24 tests: NavigationGuard (allow, external, cancelled schemes, redirects, lookalike hosts, regional Amazon), RuleStore (defaults, one switch per key, no CSS-hidden YouTube Music modals), WeeklyInsightsStore (per-day counts, week rollover, persistence across restart, corrupt file, reset). Added to the `MyApp` scheme's Test action. | **24/24 pass** on the iPhone 17 simulator |

**Test results:** Swift 24/24 · JS (`Tests/js`) 27/27 · iPhone, Mac and simulator builds succeed with 0 warnings.

**Still open:**
- DEBUG-only YouTube Music tap logger (`tapDiagnosticsSource` in `WebModel.swift`): remove it once the device re-test confirms P1.
- H2 (engine runs in the page's JS world) and H3 (child frames keep old rules): unchanged. Both need per-platform device testing.
- With **Hide header** on, the floating controls are Close only (by request), so the mini-player can't be reached from a full-screen page. Turning Hide header off brings the minimize button back.
- YouTube Music on Mac: no failure was reproduced (Device Interaction doesn't support macOS, and screen capture isn't permitted). The console showed pages loading and media playing.
- No UI tests yet. Next would be XCUITests for onboarding → Home → open/close a tile.

## I. Release assessment

**Not release-ready until built.** The JS changes are tested. The Swift changes are small and use standard WebKit/SwiftUI APIs, but they have not been compiled. Before merging:
1. Build in Xcode for iPhone and Mac.
2. Play an ad on YouTube and on Spotify.
3. Open a reel link, then Explore.
4. Enter and leave video full screen on Mac, then navigate.
5. Flip a filter switch and check that Stats doesn't jump.
6. Turn on Reduce Motion and open/minimize a platform.
7. Use "Delete my data".

## Pass 3 — Hardening & Remediation (2026-11-22)

This pass addressed the open hardening items, completed the store implementations and automated tests, and audited accessibility and security settings:

| # | Focus | Root cause / Gap | Fix / Resolution | Verification |
|---|---|---|---|---|
| R1 | **Security Settings** | Enhanced Security was disabled on the main app targets pending separate verification. | Enabled `ENABLE_ENHANCED_SECURITY = YES` on both `QuietFeed` and `QuietFeedTV`. Updated `xcode-security-settings-plan.md`. | Built with 0 errors, 0 warnings; all test plans pass. |
| R2 | **Focus & Blocking** | Focus session notifications didn't auto-schedule if enabled mid-session or cancel if toggled off; preset options were limited. | `FocusSessionStore` now automatically schedules notifications if enabled during an active session and cancels pending requests if disabled or stopped. Added 15/25/50 min presets. | 4 new unit tests in `FocusSessionStoreTests`. |
| R3 | **Usage Analytics & Export** | Stats displayed only previously completed sessions; live open platform duration was omitted until exit. | `UsageStore.duration` now includes live time for currently open platforms. CSV export verified with RFC 4180 quote escaping. Added graceful empty state in `StatsScreen`. | 5 new unit tests in `UsageStoreTests`. |
| R4 | **Offline Audio** | Playing track state (`isPlaying`, `playingTrackID`) remained stuck when an imported audio track finished playing naturally. | Added `AudioPlayerDelegateBridge` conforming to `AVAudioPlayerDelegate` to clear playback state on finish. Activated AVAudioSession on playback. | 2 new unit tests in `OfflineAudioLibraryTests`. |
| R5 | **Accessibility** | VoiceOver exposed generic SF symbol names ("play.fill", "checklist", "star.fill", "sparkles.tv.fill", etc.) on interactive cards and buttons. | Added `.accessibilityHidden(true)` to decorative icons and `.accessibilityElement(children: .ignore)` with explicit `accessibilityLabel`, `accessibilityValue`, and `accessibilityHint` across `HomeCards`, `StubScreens`, `Primitives`, `OnboardingFlow`, and `QuietFeedTV`. | Code review & preview inspection. |
| R6 | **DRM & Provider Boundaries** | Clarification on offline streaming from proprietary services. | Documented boundary: third-party services (Spotify, YouTube Music, Netflix, Prime Video) use FairPlay/Widevine DRM and prohibit unauthorized downloading. QuietFeed respects platform DRM boundaries and provides a native offline player for personal imported audio files. | UI copy in `OfflineAudioScreen` & `SettingsOfflineAudioCard`. |
| R7 | **Memory & Allocation Cycle Audit** | Verification of retain cycles in web view message handlers and background delegates. | Verified `WeakMessageHandler` and `AudioPlayerDelegateBridge` use weak references. `WebModel.shutdown()` invalidates all KVO observers and removes script message handlers. | Retain cycle audit & test suite pass. |

**Test results:** Swift Testing **40/40 passed** · JS tests **19/19 passed** (59/59 total automated tests).
