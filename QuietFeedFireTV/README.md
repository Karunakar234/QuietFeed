# QuietFeed for Fire TV

The Fire TV version of QuietFeed, built to work like TV apps: everything is driven by the remote, and there is no pointer anywhere.

| Platform | On Fire TV |
|---|---|
| YouTube, YouTube Music | **YouTube's own TV interface** (youtube.com/tv): the interface YouTube's TV apps use, so it looks and drives like the YouTube app, with sign-in by code on your phone. QuietFeed skips ads and removes Shorts. On Fire TV, YouTube Music lives inside it, as in the official app |
| Instagram | Filtered in QuietFeed. Arrows move a highlight between posts and buttons; videos play full screen with native controls |
| Netflix, Prime Video, Spotify | Opens their Fire TV app (their websites' DRM players won't run inside an app on Android), as the Apple TV version does |

How the filtering works on each:

- **YouTube's TV interface** has a different page structure from the mobile site the shared rules describe, so `YtTv.js` removes Shorts from YouTube's data before anything is drawn (every Short carries the same markers in YouTube's data on every client), and `FilterEngine.js` runs only its ad skipping, which already works on that data. Switches: Hide Shorts, Remove ads.
- **Instagram** runs the **same `rules.json` and `FilterEngine.js`** as iPhone, copied in from `../QuietFeed/Filtering` at build time, plus `TvNav.js`, which moves the highlight in the direction pressed (staying in the same row or column), scrolls to keep it in view, and skips anything the filters hid. Selecting is a real native tap.
- `NavigationGuard` is ported to Kotlin with main's hardening (https only, no top-level `blob:`/`data:`), and only the platform's own top-level page can report to the app, as on iOS.

## Using the remote

- **YouTube / YouTube Music**: exactly as the YouTube app. **Back** goes back; on YouTube's home it asks to exit.
- **Instagram**: arrows move between posts, tabs and buttons, **OK** selects, **Back** goes to the previous page, then home. In a full-screen video, **OK** plays/pauses, **left/right** skip 10 seconds.
- **Menu (≡)**, everywhere: QuietFeed's menu with Home, Reload, **Size** (Standard, Larger or Smaller, saved per platform), this platform's Filters (they apply immediately) and Close.

YouTube's TV interface is designed for a 1920-wide screen, but Fire TV's web view reports half the real width to pages, which drew everything at double size. `Viewport.js` pins its layout width to 1920 (or the Size setting's width) and the web view fits that to the screen.

Not ported: multiple accounts per platform (Android's web view shares one cookie store), background audio, the mini-player, widgets, and the Blocking and Stats tabs.

## Install without a computer

Every push that changes the Fire TV app or the shared filters rebuilds it on GitHub and publishes it at:

`https://github.com/Karunakar234/QuietFeed/releases/download/firetv-latest/QuietFeed-FireTV.apk`

On the Fire TV, install **Downloader**, allow it under **Settings → My Fire TV → Developer options → Install unknown apps**, open that link in it and choose **Install**. Updates install over the old version.

## Build and install

You need Android Studio (or the Android SDK and JDK 17).

1. Open the `QuietFeedFireTV` folder in Android Studio and let Gradle sync.
2. On the Fire TV: **Settings → My Fire TV → Developer options**, turn on **ADB debugging**. (If Developer options is hidden, go to **My Fire TV → About** and click the device name seven times.)
3. Find the TV's IP address under **My Fire TV → About → Network**.
4. Connect and install:

   ```sh
   adb connect <fire-tv-ip>:5555
   ./gradlew installDebug
   ```

   Or build an APK with `./gradlew assembleDebug` and install `app/build/outputs/apk/debug/app-debug.apk` with `adb install`.

To publish on the Amazon Appstore, build a signed release (`./gradlew assembleRelease` with your keystore) and upload it in the Amazon Developer Console.

## Supported devices

Fire OS 6 and newer (Android 7.1+, `minSdk 25`): every Fire TV Stick, Cube and Fire TV Edition TV that still gets updates.
