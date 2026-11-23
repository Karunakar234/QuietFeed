# QuietFeed for Fire TV

The Fire TV version of QuietFeed: Instagram, YouTube and YouTube Music on the TV, with the same filters as the iPhone app.

Unlike Apple TV, Fire TV has a web view, so this app does what the iOS app does rather than launching other apps. It runs the **same `rules.json` and `FilterEngine.js`** from `../QuietFeed/Filtering`, copied in at build time, so a rule change ships to both apps from one file.

## What's in it

| iOS | Fire TV |
|---|---|
| Onboarding: pick platforms | Same |
| Home with platform cards and weekly insights | Same, with remote-friendly cards |
| Filters per platform | Same switches, same defaults |
| Settings: platforms, delete insights, delete all data | Same |
| WKWebView + FilterEngine.js at document start | Android WebView + the same engine (`WebViewCompat.addDocumentStartJavaScript`) |
| NavigationGuard (redirect Shorts, block Reels) | Ported to Kotlin: same rules, same results |
| AdBlocker content rules | Same block list, enforced in `shouldInterceptRequest` |
| Touch | An on-screen pointer driven by the remote |

Not ported: multiple accounts per platform (Android's web view shares one cookie store), background audio, the mini-player, and the Blocking and Stats tabs.

## Using the remote

- **Arrows**: move the pointer. Hold to go faster. Push against the top or bottom edge to scroll.
- **Center**: tap where the pointer is. Hold for a long-press.
- **Back**: previous page, then back to QuietFeed's home.
- **Menu (≡)**: reload.
- **Play/Pause, Rewind, Fast-forward**: control the video. In full-screen video, left and right skip 10 seconds.

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
