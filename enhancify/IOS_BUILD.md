# Enhancify — iOS (App Store) build

This app is **Flutter / Dart** (not React Native). The `ios/Runner` Xcode project is included.

You need a **Mac** with Xcode to build and upload an IPA. Windows cannot compile iOS.

## What’s already set

| Item | Value |
|------|--------|
| Bundle ID | `com.mai.photo.editor.app.picture.face.art.lab` |
| Display name | Enhancify |
| Version | from `pubspec.yaml` (`1.8.7`+`19`) |
| Min iOS | 15.5 |
| Photo access | System photo picker (`image_picker` / PHPicker) |
| AdMob app id | in `ios/Runner/Info.plist` (`GADApplicationIdentifier`) |
| Privacy strings | Photo / Camera / Mic / Music in `Info.plist` |

## On a Mac (first time)

1. Install Flutter, Xcode, CocoaPods.
2. Copy this `enhancify` folder to the Mac.
3. Register the bundle id in [Apple Developer](https://developer.apple.com) → Identifiers.
4. Create the app in [App Store Connect](https://appstoreconnect.apple.com).
5. (Optional) Add an **iOS** app in Firebase / AdMob and drop `GoogleService-Info.plist` into `ios/Runner/` if you use Firebase Analytics on iOS.
6. Open signing in Xcode:

```bash
cd enhancify
flutter pub get
cd ios
pod install
cd ..
open ios/Runner.xcworkspace
```

In Xcode: **Signing & Capabilities** → your Team → Automatic signing.

7. Build / archive:

```bash
flutter build ipa --release
```

IPA path: `build/ios/ipa/*.ipa` — upload with Transporter or Xcode Organizer.

## Do not use React Native

The full UI, ads, IAP, ML Kit, and editor are already in Flutter. Rewriting in React Native would mean rebuilding the whole app.
