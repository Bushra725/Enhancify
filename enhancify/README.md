# Enhancify: AI Photo Enhancer (Flutter)

An AI photo enhancer app with the same features and flows as the reference app,
in an original red and maroon design. It is Android-first and also builds for iOS.

## Features

| Area | What it does |
|---|---|
| Onboarding | Welcome, "Where did you discover us?" survey (with a free-text "None of these" answer), privacy consent (Accept / Refuse / Customize), gender, then an animated surprise gift that reveals a 2-week trial offer |
| Home | Photos/Videos tabs, gallery grid with paging, pull-to-refresh, limited-access support, system picker button, bottom bar (Enhance, AI Photos, AI Filters, All Tools) |
| Enhance photo | Preview dialog, then the "Uploading image..." modal, AI face restore + upscale, interstitial ad (free users), before/after slider, variants (Enhance / Natural / Ultra HD 4x Pro), save, share, auto-save |
| Enhance video (Pro) | Preview, duration check (60 s), AI video upscale, player with Enhanced/Original toggle, save, share |
| AI Photos | Pick Preset screen with gender switch and a first-run tooltip, category chips, 6 packs × 6 styles, preset detail with "Use This Preset" (free with a rewarded ad), "Get Full Pack" (Pro), AI profile of up to 8 selfies, results viewer, "My AI Photos" history |
| AI Filters | 12 styles (Anime, 3D Cartoon, Oil, Watercolor, Sketch, Comic, Cyberpunk, and more). Some are Pro |
| All Tools | Enhance Photos/Videos, AI Photos, AI Filters, Colorize old photo, Upscale 4x |
| Monetization | Lite / Pro weekly and yearly subscriptions, free-trial offer, Restore Purchases, redeem codes, daily free limits with a "watch an ad for one more" option, AdMob interstitial and rewarded ads |
| Settings | Pro card, Delete AI Profile, Share App, social links, Help Center, Contact Support, Suggest a Feature, Subscription Info, Redeem Code, Photos Permissions, Enhancer Preferences (strength, 1x/2x/4x, background, auto-save), Terms, Privacy, Privacy Preferences, Open Source Libraries |

**Demo mode.** With no AI backend configured, every screen still works and "AI" results
are simulated on the device. This lets you test the whole app before you pay for anything.

## 1. Set up (one time)

Requirements: Flutter (latest stable), Android Studio with an Android SDK, and a phone or emulator.

```bash
# Windows (PowerShell), in this folder:
powershell -ExecutionPolicy Bypass -File .\setup.ps1
# macOS / Linux:
./setup.sh
```

The script does four things:

1. It runs `flutter create .`, which generates the `android/` and `ios/` folders and keeps your `lib/`.
2. It runs `flutter pub get`.
3. It runs `dart run tool/setup_platforms.dart`, which adds permissions, the AdMob app id, and minSdk 24.
4. It runs `dart run flutter_launcher_icons`, which generates the app icon.

Then run the app:

```bash
flutter run            # demo mode
```

## 2. Connect real AI (Replicate)

1. Create an account at replicate.com, add billing, and copy your API token.
2. **Quick test (development only)**:
   `flutter run --dart-define=REPLICATE_API_TOKEN=r8_xxx`
3. **Production**: deploy `server/`. It is a zero-dependency Node 18+ proxy that keeps the token off the phone:
   ```bash
   cd server
   REPLICATE_API_TOKEN=r8_xxx APP_KEY=long-random-string node server.js
   node test.js   # self-test with a fake upstream
   ```
   It runs on Render, Railway, Fly.io or any VPS. Then build the app with:
   ```bash
   flutter build apk --release \
     --dart-define=BACKEND_URL=https://your-server.example.com \
     --dart-define=BACKEND_APP_KEY=long-random-string
   ```

Models are set in `lib/config/ai_models.dart`:

- Enhance: `sczhou/codeformer`
- Ultra HD: `nightmareai/real-esrgan`
- Filters, AI Photos and Colorize: `black-forest-labs/flux-kontext-pro`
- Video: `lucataco/real-esrgan-video`

At runtime the app reads each model's input schema. You can swap a model by editing that
one file, plus `ALLOWED_MODELS` on the server.

## 3. Before you publish

- [ ] **Ads**: in `lib/config/app_config.dart`, replace the Google **test** ad unit ids. Also replace the app id in `tool/templates/AndroidManifest.xml` and `tool/setup_platforms.dart` (iOS), then re-run the setup script.
- [ ] **Subscriptions**: in Play Console, create `enhancify_lite_weekly`, `enhancify_lite_yearly`, `enhancify_pro_weekly` and `enhancify_pro_yearly`. Add a **2-week free-trial offer** to `enhancify_pro_weekly`. The app detects the offer automatically and hides the trial wording when none exists.
- [ ] **Links**: in `app_config.dart`, set the support email and the Terms, Privacy and Help URLs.
- [ ] **Package id**: the setup script uses `com.theoccess.enhancify`. To change it, edit `setup.*` and `AppConfig.androidPackage`.
- [ ] **Release signing**: see flutter.dev → "Build and release an Android app".
- [ ] **Receipt checks**: for production, verify receipts on your server. The client check is the usual starting point.
- [ ] **Preview images**: optionally add real preview photos for AI Photos presets with `imageUrl:` in `lib/data/catalog.dart`. By default the presets use branded gradient tiles.

In debug builds, tapping a plan while the store has no products grants that tier locally,
so you can test the Pro flows. Release builds never do this.

## Project map

```
lib/
  config/     app_config.dart (everything to customize), ai_models.dart
  services/   app_state (prefs, limits), ai_service, replicate_service,
              purchase_service, ads_service, media_service
  screens/    onboarding/, home/, enhance/, ai_photos/, ai_filters/,
              paywall/, settings/, tools/
  widgets/    common UI, gallery grid, before/after slider, processing dialog
server/       Replicate proxy (Node, no dependencies) + test
tool/         platform setup script + AndroidManifest template
```

## Working in Cursor

Open the folder in Cursor, run the setup script once, and use `flutter run`. Good first prompts:

- "Add real preview images to the presets in lib/data/catalog.dart"
- "Add a new AI filter called X to aiFilters"

Keep colors in `lib/theme/app_theme.dart` (`AppColors`).
