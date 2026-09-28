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

## Photo editor & collage (v3)

- **Theme:** light, built on **#EA026A**. It uses blush and berry pinks, with apricot, lavender and mint as accents. All colors are in `lib/theme/app_theme.dart` (`AppColors`, `AppPalette.light`).
- **Collage:** 19 layouts, including 12 inspired by Pinterest:
  - Scrapbook, Memories (curved caption), Torn paper and Swipe.
  - 19 vibes, Polaroid stack, Cut-out and Dark grid.
  - Sage dream, Pink bows (scalloped frames), July (tilted polaroids) and Arches.
  - Classic grids with a spacing slider.
  - In every layout you can pinch to zoom each photo, tap a frame to replace its photo, and change the background color.
  - Collages save at 2160 px wide.
- **Text:**
  - 22 bundled fonts that work offline.
  - Colors from swatches or a rainbow slider.
  - Styles: shadow, outline, label, highlight and letter tiles.
  - **Curved text**, from a smile curve to a full arch.
  - 24 ready-made caption templates, such as "Feeling 19 vibes", "photo dump" and "JULY".
- **Emoji:** the full emoji keyboard, 1,849 emoji up to Emoji 14. It has search, recently used emoji and skin tones.
- **Stickers:** 102 aesthetic stickers: bows, hearts, flowers, washi tape, polaroids, doodles, food and word stickers.
  - **Make a sticker from your own photo** (Stickers → From my photo, or Text → Photo sticker).
  - The AI cut-out keeps only the person and adds a white outline. It uses on-device ML Kit selfie segmentation.
  - You can also cut the photo into a circle, heart, star or rounded shape.
- **Avatar:** a Snapchat-style avatar builder with 14 categories: face, skin, hair, hair color, eyes, brows, nose, lips, beard, glasses, earrings, headwear, outfit and outfit color. It also has a Shuffle button. Your avatar comes in 14 sticker poses: Hi, Love, LOL, Cool, Kiss, OMG, Sleepy and more.
- **Draw:** pen, marker and neon brushes, any color, adjustable size, undo stroke and clear.
- **Moving items:** you can drag, pinch and rotate every text, emoji, sticker and avatar. Selected items show a corner handle for one-finger resize and rotate.
- **Adjust panel:** one adjustment at a time with a value readout and reset. It no longer runs off the right edge of the screen.
- **Saving:**
  - Edits save at full resolution (up to 3072 px), and overlays are drawn at the same resolution.
  - Crop is now true 1:1 or 9:16.

iOS note: the AI cut-out uses Google ML Kit, which needs iOS 15.5 or newer (set `platform :ios, '15.5'` in `ios/Podfile`). Android works as is.

Regenerating art (optional): the stickers and avatar are generated from vector sources by
`tool/art/stickers.py` and `tool/art/avatar_gen.py`. You need Python and Playwright to run them.

## New in v5

- **Restore → Smooth fill / Texture fill** (fixed; now the same on Android and iOS):
  - **Texture fill** works like Photoshop's content-aware fill. It rebuilds the marked area from matching patches of the photo, then blends the edges so there's no seam.
  - **Smooth fill** blends the surrounding colors seamlessly and adds the photo's own grain. Best for scratches, dust and plain areas.
  - **Paint/Eraser**: an eraser was added for the marks.
- **Remove object**: uses the same engine, with Texture (default) or Smooth. The eraser trims your mark before removing.
- **Avatars for boys**: a Girl/Boy switch in the avatar builder.
  - New for boys: an angular face shape, 6 hairstyles (quiff, spiky, fade, slick, fringe, man bun), straight brows, full and chevron beards, and 4 outfits (jacket, polo, suit, kurta).
  - Shuffle keeps the chosen gender.
- **Makeup**:
  - The panel now has proper side padding and a clear check on the selected color.
  - More shades, plus a custom color picker. Picking a color shows it straight away.
  - Lipstick follows the real lip outline, leaves an open mouth or teeth untouched, and tints while keeping the lips' own light and shadow.
  - Eyeliner (with a small wing), eyeshadow, brows and blush scale to the face size.
- **Brush colors**: a full color picker (shade square, hue bar, recent colors), a check on the selected swatch, and a light-to-dark shade strip. The same picker is used in Draw, Text and Collage.
- **Draw eraser**: a new "Eraser" brush that erases only your drawing, not the photo.
- **Crop & rotate** (editor "Crop" tab, or More → Crop & ratio / Rotate & flip):
  - Crop: Free, Original, 1:1, 4:5, 3:4, 2:3, 9:16, 16:9, 4:3, 3:2 and 5:4, with a draggable, resizable crop box.
  - Rotate: turn left or right, flip up/down or left/right, straighten with a slider, or twist with two fingers to rotate freely.
- **Remove background**: works like Canva's, and the result shows on screen right away.
  - People are detected by ML Kit. Objects use OpenCV GrabCut on Android and a color model on iOS.
  - Pick a new background: none (transparent PNG), a color, blur, or a photo.
  - Refine with Erase/Restore brushes, then Done opens save/share.
- **Beauty** (editor "Beauty" tab, and on the home screen): Snapchat-style and face-aware.
  - Skin smoothing that keeps pore texture, glow, even tone, bright eyes, whiter teeth, lip color, big eyes, slim face and a slimmer nose.
  - Presets: Natural, Glow, Snap, Doll, Soft and Sculpt. Hold the compare button to see the original.
- **Languages**: 23 more (29 in total), and the picker now scrolls. Long technical messages still show in English.
  - New: German, Italian, Portuguese, Russian, Turkish, Indonesian, Malay, Bengali, Punjabi, Persian, Pashto, Chinese, Japanese, Korean, Vietnamese, Thai, Tamil, Filipino, Swahili, Dutch, Polish, Gujarati and Marathi.
  - Persian and Pashto display right-to-left.
- **Share everywhere**:
  - The Enhance/Restore result, AI Photos result and video result screens now have a "Share to" row with WhatsApp, Instagram, Facebook, TikTok and More.
  - The editor, collage, background remover, remove object and beauty tools finish on the Save/Share/Post screen.

## New in v4

- **Pink app icon**: launcher icons for Android (including the adaptive icon) and iOS now use the app's pink (#EA026A).
- **Remove object** (editor "Remove" tab, More, or the home quick tools):
  - Brush over an object, draw a lasso around it, or use Erase to fix the mark. Pinch to zoom, and hold the compare button to see the original.
  - **Remove** runs on the phone: OpenCV on Android, a smooth Dart fill on iOS.
  - **AI remove** uses the free Cloudflare worker for large or detailed areas. Only the marked area is replaced, so the rest of the photo keeps its full resolution.
- **Make GIF** (fixed): a new screen with a live preview.
  - Styles: Zoom pulse, Pan & zoom, Shake, Glitch, Sparkle and Slideshow (add up to 10 photos).
  - Speed and size options. It builds in the background, so the app no longer freezes.
- **Passport photo**:
  - Sizes: UK/EU/Schengen, Pakistan, India, USA, India visa, Canada, China, Australia, Saudi/UAE, and ID 25×35. Photos are exported at 300 dpi.
  - Face detection places the head automatically, and on-screen guides show the head area. Size and position sliders let you adjust it.
  - Background: white, off-white, light blue, grey, blue or red, or keep the original.
  - Print sheet: saves a 6×4 in sheet with as many copies as fit.
- **Photo + music**:
  - Pick any song from your phone, choose 10, 15, 30 or 60 s and the start point, and preview it.
  - Makes an MP4 (H.264 + AAC) with an optional slow zoom and fade that Reels, Stories, TikTok and WhatsApp accept.
  - Powered by `ffmpeg_kit_flutter_new`, which adds roughly 30 MB per ABI. Build with `flutter build appbundle` so Play Store users download only their own ABI.
- **Done screen**: the editor and collage now finish with **Done**, which opens a share screen with:
  - Save and Share.
  - One-tap posting to Instagram, Facebook, WhatsApp, TikTok and Snapchat. On Android the app opens directly. On iOS, and when an app isn't installed, the share sheet opens instead.
  - Add music and Make GIF.
- **Pink watermark**: the watermark (More → Watermark) is now the brand pink with a thin white outline. It is sized to the photo and placed bottom-right.

Test on a real device: posting to social apps, music videos (ffmpeg) and removal.

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
