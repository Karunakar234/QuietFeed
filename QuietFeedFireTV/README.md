# QuietFeed for Fire TV

The Fire TV version of QuietFeed. It works like a TV app: the remote moves a highlight between videos and buttons, choosing a video plays it full screen, and Menu (≡) opens the app menu.

| Platform | On Fire TV |
|---|---|
| YouTube | Filtered in QuietFeed. Videos open full screen with native controls |
| YouTube Music, Instagram | Filtered in QuietFeed |
| Netflix, Prime Video, Spotify | Opens their Fire TV app (their websites' DRM players won't run inside an app on Android), as the Apple TV version does |

The filtered platforms run the **same `rules.json` and `FilterEngine.js`** from `../QuietFeed/Filtering`, copied in at build time, so a rule change ships to iPhone and Fire TV from one file. `NavigationGuard` is ported to Kotlin with main's hardening (https only, no top-level `blob:`/`data:`), and only the platform's own top-level page can report to the app, as on iOS.

`app/src/main/assets/TvNav.js` is the Fire TV-only part: it finds everything selectable on the page, moves the highlight in the direction pressed (staying in the same row or column), scrolls to keep it in view, and skips anything the filters hid. Selecting is a real native tap, so sites treat it as a person's tap.

## Using the remote

- **Arrows**: move between videos, tabs and buttons.
- **OK**: select. In a full-screen video: play/pause.
- **Left / Right in full-screen video**: skip back or forward 10 seconds. **Up / Down** show the progress bar.
- **Back**: leave full screen, then the previous page, then back to QuietFeed's home.
- **Menu (≡)**: Home, Reload, this platform's Filters, Pointer mode (a free pointer for anything the highlight can't reach), Close.
- **Play/Pause, Rewind, Fast-forward**: control the video.

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
