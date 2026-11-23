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

## Pass 4 — Reliability, privacy and native integration (2026-11-23)

Baseline before changes: build OK (0 warnings), Swift 41/41, JS 21/21. Enhanced Security was already `YES` on `QuietFeed` (the "still disabled" note was stale).

| # | Enhancement | User benefit | Complexity | Security / privacy | iOS | Regression risk |
|---|---|---|---|---|---|---|
| E1 | **Resume card** (`HomeScreen.ResumeCard`, finishes the `PlayerSession` recovery keys) | After a crash or a system kill, Home offers "Resume {platform}". It's never reopened automatically, so a crashing page can't crash the app in a loop | Low | Stores only the platform id (no URLs) for 24 h. Cleared on Close, Not now, sign-out and Delete my data | 27.2 (deployment target) | Low |
| E2 | **Crash-loop guard** (`WebModel.webViewWebContentProcessDidTerminate`) | A page whose web process dies more than twice in 60 s shows an error instead of reloading forever | Low | None | 27.2 | Low |
| E3 | **Offline auto-retry** (`ConnectivityMonitor`, `LoadFailurePolicy`) | An offline page reloads by itself when the network returns. Timeouts and unreachable-host errors retry twice (after 2 s, then 6 s) before the error shows | Medium | None; `NWPathMonitor` reads path status only | 27.2 | Medium: retry timing still needs checking on a flaky device network |
| E4 | **Wider search** (`SearchResults.swift`) | Home search now also finds filter switches (they can be toggled in place) and imported audio (playable in place) | Low | Local only; nothing leaves the device | 27.2 | Low |
| E5 | **Sign out of one platform** (`AccountsScreen`) | Signs out of a single service without wiping everything | Low | Deletes only that account's `WKWebsiteDataStore`; asks for confirmation first. `WebsiteDataCleaner` is now shared with Delete my data | 27.2 | Low |
| E6 | **"What works here"** (`PlatformCapabilities`) | An accurate per-platform feature list, derived from the same code paths the web view uses. Offline downloads are always shown as Not available (DRM) | Low | None | 27.2 | Low |
| E7 | **App lock** (`AppLock`, `LockCover`) | Opt-in Face ID / Touch ID / passcode lock on launch and after backgrounding. Hides content in the app switcher. Audio keeps playing | Medium | `.deviceOwnerAuthentication` (falls back to the passcode). Turning it on or off requires a successful authentication. Cancelling doesn't re-prompt in a loop. `NSFaceIDUsageDescription` added | 27.2 | Medium: needs a physical-device check with real Face ID and PiP |
| E8 | **Siri & Shortcuts** (`AppIntents.swift`) | Start Focus (1–240 min), End Focus and Open {Platform} from Siri, Spotlight, Shortcuts and the Action button | Medium | Open respects Focus blocking. Dependencies are registered in `App.init()`. Background intents never show UI | 26+ (`supportedModes`) | Low–medium: phrases are a public contract once shipped |
| E9 | **Diagnostics & benchmarks** | `Page load` signpost intervals (Points of Interest) per platform. XCTest `measure` benchmarks for rules decode, 1,000 navigation decisions and search | Low | Platform id logged as public; no URLs | 27.2 | None (tests only) |

**Validation (this pass):** build OK with 0 warnings · Swift **62/62** (41 existing + 21 new) · JS **21/21** · the app launched in the iPhone simulator with no errors or faults in the console. Benchmarks (simulator, Debug, no baseline set yet): rules decode <1 ms; 1,000 `NavigationGuard.decide` calls ≈ 9 ms; 5 search queries over every filter plus 2,000 tracks ≈ 11 ms.

**Not verified:** none of the new screens were checked visually. Not tested on a physical device: Face ID, background audio, PiP, auto-retry on a real network change, Siri voice phrases. No Instruments runs (Time Profiler, Allocations, Leaks, Energy).

**Needs approval (not started):**
- Widgets / Focus Live Activity: needs a new Widget Extension target plus an App Group so the extension can read Focus state.
- iCloud sync: `PlatformSetting.platformID` and `Account.id` use `@Attribute(.unique)`, which CloudKit-backed SwiftData doesn't support. Syncing needs a schema migration (dedupe in code) plus the iCloud/CloudKit entitlement. Website cookies can't sync and shouldn't.

**Follow-up (same day):** the app-level `.preferredColorScheme(.dark)` is removed, so the Settings appearance picker now works. Text on glass or the backdrop uses `Theme.color.text`/`textMuted` and the new adaptive `Neon.glow`. `AuroraBackground` has a light variant. Text on fixed dark artwork (Focus hero, recommendation art) stays white. Deleted unused views: `HomeScreen.header`/`searchRow`, `GlassScreenHeader`, `quietFeedNavigationChrome()`, and six `Settings*Card` views. Checked in Light and Dark previews of the Home cards; Light preview of onboarding. Build 0 warnings, Swift 62/62.

### Light mode check and contrast audit (2026-11-23)

- **Previews:** new `PreviewSupport.previewEnvironment()` (DEBUG only). It supplies the bundled rules, an in-memory store seeded like the app, and stores that use a scratch folder and scratch defaults, so a preview never touches real data. The "Pick Platforms" preview had shown an empty grid because nothing loaded the rules; it now shows all six platforms. Added Light-mode previews for Stats, Blocking, Settings and Accounts, and looked at each one.
- **Contrast** (WCAG 2.1 ratios, computed from the colour values in `Theme.swift` and `Neon`; alpha colours composited over their real background; not a pixel measurement):

| Pair (Light) | Before | After |
|---|---:|---:|
| System `.secondary` text on grouped card | 3.30:1 (fail) | replaced by `Theme.color.textMuted`: 5.88:1 |
| System `.tertiary` text on grouped card | 1.71:1 (fail) | replaced by `Theme.color.textMuted`: 5.88:1 |
| Platform card subtitle, worst case (Netflix/Spotify navy wash) | 2.29:1 (fail) | 5.05:1 (Light wash 35% → 12%) |
| Body text / muted text / `Neon.glow` on white | 17.99 / 6.56 / 6.25:1 | unchanged |

  Dark mode and the white-on-artwork pairs were already 5.6:1 or better and are unchanged. Platform icons (non-text, 3:1 needed) are 3.74:1 or better.
- **Not audited:** Form section headers and footers use Apple's system styling, which I left as is. Increased Contrast mode wasn't checked.

### Widgets, Live Activity, Form headers, Increased Contrast, device run (2026-11-23)

- **Focus widget** (new `QuietFeedWidgetsExtension` target, embedded in QuietFeed). Home Screen small/medium; Lock Screen inline, circular and rectangular (iOS); small/medium on Mac. It shows the time left, counting down on its own via `Text(timerInterval:)`, or "No session running" / "Focus Mode is off". The timeline is the running entry plus an idle entry at the end time; the app reloads it on start, stop and launch.
- **Focus Live Activity** (iOS): Lock Screen and Dynamic Island countdown. It goes stale at the end time and then reads "Focus complete". It's ended when the session stops, when Focus Mode is turned off, and at launch if the session already finished. `StartFocusSessionIntent` adopts `LiveActivityIntent` so Siri can start one in the background. `NSSupportsLiveActivities` was added to the app.
- **App Group** `group.com.kanna.quietfeed` on both targets. Only the session end time and the Focus on/off switch are written to it; platforms, accounts and usage stay in the app's own container. Only the app's real `FocusSessionStore` publishes; tests and previews use scratch defaults and never start Live Activities.
- **Shared contract:** the App Group ID, the keys and `FocusActivityAttributes` are mirrored in `QuietFeed/Models/FocusSurfaces.swift` and `QuietFeedWidgets/FocusShared.swift`. Both targets use synchronized folders and no tool here can add one file to two targets. Keep the two files identical, or move the shared file into both targets' membership in Xcode.
- **Extension settings:** Enhanced Security `YES` (matches the app); macOS minimum 26.7.2 (matches the app; the template had 27.2); display name "QuietFeed".
- **Form headers and footers** now use `ThemedSection` (`Primitives.swift`): `Theme.color.textMuted`, 5.88:1 on the grouped background, replacing the system grey at about 3.3:1. The offline-audio error text moved from system red (3.55:1) to `Theme.color.danger` (5.71:1).
- **Increased Contrast:** Settings and the Home cards were rendered in Light and Dark. The system controls get borders; QuietFeed's own colours don't change, but they already pass AA in both modes. A real high-contrast variant belongs in the design tokens that generate `Theme.swift`; those tokens aren't in this repo.
- **Physical device:** built, signed, installed and launched on "Karunakar's iPhone" (iOS 27.2). Automatic signing accepted the new App Group. The console had one App Group defaults message (`kCFPreferencesAnyUser … detaching from cfprefsd`) and WebKit sandbox/cfprefsd messages from the web content process. No crash.
- **Validation:** build 0 warnings · Swift 62/62 (`MyApp` scheme; target creation had switched the active scheme to the extension, now switched back) · previews of the small widget and the expanded Dynamic Island checked.
- **Still needs a person holding the device:** adding the widget and watching it count down; a Live Activity on the Lock Screen and in the Dynamic Island (the Lock Screen preview didn't draw the navy tint, so white-on-tint is unconfirmed); real Face ID unlock; Siri voice phrases; background audio and Picture in Picture for each service; auto-retry when Wi-Fi drops and returns.

### Launcher widgets (2026-11-23, from the "QuietFeed Widgets" mockup)

| Widget | Sizes | What it does |
|---|---|---|
| Favorite Apps | Small (4 icons), Medium (6 icons with names) | Opens a platform in QuietFeed |
| Quick Apps | Small (4 icons) | The four most recently opened platforms |
| Open QuietFeed ("Entertainment") | Small | Opens the app |
| Library | Small | Favourites count, platforms opened in the last 7 days, all switched-on platforms |
| Extended Launcher | Large | 6 app tiles plus Open QuietFeed / Favorites / Recently Opened (reopens the last platform) / All Apps |

- **Data:** the app publishes the switched-on platforms (id, name, symbol, favourite flag, last opened) to the App Group whenever those settings change, and reloads the launcher widgets only when the data actually changed. Before the first publish the widgets show all six platforms in the default order.
- **Taps:** icons are `Button(intent: OpenPlatformFromWidgetIntent)`, because small widgets can't hold `Link`s. The intent is declared in both targets. The app's copy hands the platform to `IntentRouter`; the extension's copy writes it to the App Group, and the app takes it when it becomes active (only if under 30 s old). Shortcut rows and the widget background use the new `quietfeed://` URL scheme (`quietfeed://open/<id>`, `quietfeed://home`). Unknown IDs are ignored, and the Focus block now also applies to widget and link opens, with the same alert as Home.
- **Icons:** each platform's brand colour with QuietFeed's own SF Symbol, not the services' trademarked logos.
- **Validation:** build 0 warnings · Swift 68/68 (6 new deep-link tests) · all six launcher layouts rendered in previews · installed and launched on "Karunakar's iPhone" with no new console errors. Not yet tapped on a real Home Screen.
