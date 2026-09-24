# Free AI backend (Cloudflare Workers AI)

This Worker powers the app's AI features at no cost. It covers photo enhance/restore,
AI Filters, AI Photos, Colorize and HD Restore. It runs the **FLUX.2 [klein] 4B** model
on Cloudflare's free daily allowance, and no credit card is needed.

## What "free" means

| Item | Free amount |
|---|---|
| Workers AI | 10,000 neurons per day, reset at 00:00 UTC. That is about **90 photo edits a day** at 1024 px |
| Worker requests | 100,000 per day |

- **The allowance is shared.** It belongs to your Cloudflare account, so all your app's users draw from the same ~90 edits a day. That is fine for testing and a small launch. When you grow, upgrade to the $5/month Workers plan, which costs about $0.011 per 1,000 neurons (roughly $0.001 per edit). You don't have to change any code.
- **Input size.** The model accepts input photos under 512×512, and the app resizes them automatically. The output is up to 1024 px. "Enhance" is therefore an AI *restore*: it is great for old, blurry or low-res photos, but it is not a pixel-perfect 4× upscale of a 12 MP photo.
- **Video is not included.** Video enhance only works with the paid Replicate option. The app hides it automatically when you use the free backend.

## Deploy option A: no coding, in the dashboard (about 5 minutes)

1. Create a free account at **dash.cloudflare.com**.
2. Go to **Workers & Pages → Create → Create Worker**. Name it `enhancify-ai` and click **Deploy**.
3. Click **Edit code**. Delete everything, paste the contents of `worker.js`, and click **Deploy**.
4. Go to **Settings → Bindings → Add → Workers AI**. Set the variable name to `AI`, then save.
5. Go to **Settings → Variables and Secrets → Add**. Choose type **Secret**, name it `APP_KEY`, and give it a long random value, e.g. `enh_7f3k9...`. Save.
6. Open `https://enhancify-ai.<your-subdomain>.workers.dev/health` in a browser. You should see `{"ok":true,...}`.

## Deploy option B: command line

```bash
cd cloudflare
npx wrangler login
npx wrangler deploy               # prints your https://...workers.dev URL
npx wrangler secret put APP_KEY   # paste a long random string
node test.mjs                     # local test with a fake AI (optional)
```

## Connect the app

```bash
flutter run \
  --dart-define=CF_WORKER_URL=https://enhancify-ai.<your-subdomain>.workers.dev \
  --dart-define=CF_APP_KEY=<the same APP_KEY>
```

Use the same two `--dart-define` flags with `flutter build apk --release`. In Cursor, you
can add them to `.vscode/launch.json` under `"args"` so every run uses them.

## Protecting the free allowance

- The app already limits each free user per day. Change the limits in `lib/config/app_config.dart` with `freeEnhancementsPerDay` and `freeFiltersPerDay`.
- The Worker limits each IP address to 30 requests per minute and requires `APP_KEY`.
- When the daily allowance runs out, users see: "Daily free AI limit reached. Try again tomorrow."
