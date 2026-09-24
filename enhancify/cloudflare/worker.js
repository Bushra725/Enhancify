// Enhancify FREE AI backend — a Cloudflare Worker using Workers AI.
//
// Costs nothing on Cloudflare's free plan:
//   * Workers free plan: 100,000 requests / day
//   * Workers AI: 10,000 "neurons" / day free (≈ 90 photo edits / day with
//     FLUX.2 [klein] 4B at 1024px output). Shared by ALL your app's users.
//
// Endpoint used by the app:
//   POST /v1/edit   multipart/form-data
//     image   : the photo (JPEG/PNG, must be < 512x512 — the app resizes it).
//               Repeat the field (up to 4) to send several reference photos.
//     prompt  : what to do ("restore this photo", "turn into anime", ...)
//     width   : output width  (optional, default 1024)
//     height  : output height (optional, default 1024)
//   header x-app-key: <APP_KEY secret>
//   -> 200 { "image": "<base64 png/jpeg>" }
//
// Deploy: see cloudflare/README.md (npx wrangler deploy).

const MODEL = '@cf/black-forest-labs/flux-2-klein-4b';
const MAX_SIDE = 1024;
const MAX_UPLOAD = 5 * 1024 * 1024;
const RATE_PER_MIN = 30; // per IP, per Worker isolate (best effort)

const hits = new Map();
function rateLimited(ip) {
  const now = Date.now();
  const list = (hits.get(ip) || []).filter((t) => now - t < 60_000);
  list.push(now);
  hits.set(ip, list);
  if (hits.size > 5000) hits.clear();
  return list.length > RATE_PER_MIN;
}

function json(status, obj) {
  return new Response(JSON.stringify(obj), {
    status,
    headers: { 'content-type': 'application/json' },
  });
}

// Output sides must be multiples of 16 and within limits.
function side(v, fallback) {
  const n = Math.round(Number(v) || fallback);
  const clamped = Math.max(256, Math.min(MAX_SIDE, n));
  return Math.floor(clamped / 16) * 16;
}

function toBase64(buf) {
  let s = '';
  const bytes = new Uint8Array(buf);
  for (let i = 0; i < bytes.length; i += 0x8000) {
    s += String.fromCharCode.apply(null, bytes.subarray(i, i + 0x8000));
  }
  return btoa(s);
}

export async function handle(request, env) {
  const url = new URL(request.url);

  if (url.pathname === '/health') {
    return json(200, { ok: true, model: MODEL });
  }
  if (url.pathname !== '/v1/edit' || request.method !== 'POST') {
    return json(404, { detail: 'Not found' });
  }
  if (env.APP_KEY && request.headers.get('x-app-key') !== env.APP_KEY) {
    return json(401, { detail: 'Unauthorized' });
  }
  const ip = request.headers.get('cf-connecting-ip') || 'local';
  if (rateLimited(ip)) {
    return json(429, { detail: 'Too many requests. Please wait a minute.' });
  }
  const len = Number(request.headers.get('content-length') || 0);
  if (len > MAX_UPLOAD) return json(413, { detail: 'Image too large' });

  let form;
  try {
    form = await request.formData();
  } catch (_) {
    return json(400, { detail: 'Expected multipart/form-data' });
  }
  // 1-4 reference images, all sent as "image".
  const images = form.getAll('image').filter((f) => f && typeof f !== 'string').slice(0, 4);
  const prompt = (form.get('prompt') || '').toString().trim();
  if (images.length === 0) {
    return json(400, { detail: 'Missing image' });
  }
  if (!prompt || prompt.length > 2000) {
    return json(400, { detail: 'Missing or too long prompt' });
  }

  const body = new FormData();
  body.append('prompt', prompt);
  for (let i = 0; i < images.length; i++) {
    const type = images[i].type && images[i].type.startsWith('image/') ? images[i].type : 'image/png';
    const blob = new Blob([await images[i].arrayBuffer()], { type });
    body.append(`input_image_${i}`, blob, `input_${i}.${type === 'image/jpeg' ? 'jpg' : 'png'}`);
  }
  body.append('width', String(side(form.get('width'), 1024)));
  body.append('height', String(side(form.get('height'), 1024)));

  try {
    // Serialize the form so we can hand Workers AI the exact multipart body.
    const req = new Request('http://form', { method: 'POST', body });
    const result = await env.AI.run(MODEL, {
      multipart: {
        body: req.body,
        contentType: req.headers.get('content-type'),
      },
    });
    const out = result && (result.image || (result.result && result.result.image));
    if (typeof out === 'string' && out.length > 0) {
      return json(200, { image: out });
    }
    if (out instanceof ArrayBuffer || out instanceof Uint8Array) {
      return json(200, { image: toBase64(out) });
    }
    return json(502, { detail: 'The AI returned no image.' });
  } catch (e) {
    const msg = String((e && e.message) || e);
    // Daily free allocation used up.
    if (/neuron|quota|limit|4006/i.test(msg)) {
      return json(503, { detail: 'Daily free AI limit reached. Try again tomorrow.' });
    }
    if (/nsfw|safety|flagged/i.test(msg)) {
      return json(422, { detail: 'This photo could not be processed. Try another one.' });
    }
    return json(502, { detail: 'AI error: ' + msg.slice(0, 200) });
  }
}

export default {
  fetch: (request, env) => handle(request, env),
};
