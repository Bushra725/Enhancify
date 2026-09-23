// Enhancify AI proxy — zero dependencies, Node 18+.
//
// Forwards a small, allow-listed subset of the Replicate API so the app never
// sees your REPLICATE_API_TOKEN.
//
//   REPLICATE_API_TOKEN=r8_xxx APP_KEY=some-long-secret node server.js
//
// App side: flutter run --dart-define=BACKEND_URL=https://your-host \
//                       --dart-define=BACKEND_APP_KEY=some-long-secret
'use strict';

const http = require('http');

const PORT = Number(process.env.PORT || 8787);
const TOKEN = process.env.REPLICATE_API_TOKEN || '';
const APP_KEY = process.env.APP_KEY || '';
const UPSTREAM = process.env.REPLICATE_BASE || 'https://api.replicate.com';
const MAX_UPLOAD = Number(process.env.MAX_UPLOAD_MB || 100) * 1024 * 1024;
const RATE_PER_MIN = Number(process.env.RATE_PER_MIN || 30);

// Only these models can be used through the proxy (keep in sync with
// lib/config/ai_models.dart).
const ALLOWED_MODELS = new Set(
  (process.env.ALLOWED_MODELS ||
    'sczhou/codeformer,nightmareai/real-esrgan,black-forest-labs/flux-kontext-pro,lucataco/real-esrgan-video')
    .split(',')
    .map((s) => s.trim())
    .filter(Boolean),
);

// Version ids we have seen for allowed models (filled by GET /models/...).
const allowedVersions = new Set();

// ------------------------------------------------------------ rate limit
const hits = new Map();
function rateLimited(ip) {
  const now = Date.now();
  const list = (hits.get(ip) || []).filter((t) => now - t < 60_000);
  list.push(now);
  hits.set(ip, list);
  return list.length > RATE_PER_MIN;
}
setInterval(() => {
  const now = Date.now();
  for (const [ip, list] of hits) {
    if (!list.some((t) => now - t < 60_000)) hits.delete(ip);
  }
}, 60_000).unref();

// ------------------------------------------------------------ helpers
function send(res, status, obj) {
  const body = JSON.stringify(obj);
  res.writeHead(status, {
    'content-type': 'application/json',
    'content-length': Buffer.byteLength(body),
  });
  res.end(body);
}

function readBody(req, limit) {
  return new Promise((resolve, reject) => {
    const chunks = [];
    let size = 0;
    req.on('data', (c) => {
      size += c.length;
      if (size > limit) {
        reject(Object.assign(new Error('Payload too large'), { status: 413 }));
        req.destroy();
        return;
      }
      chunks.push(c);
    });
    req.on('end', () => resolve(Buffer.concat(chunks)));
    req.on('error', reject);
  });
}

async function forward(res, method, path, { body, contentType } = {}) {
  const headers = { authorization: `Bearer ${TOKEN}` };
  if (contentType) headers['content-type'] = contentType;
  const r = await fetch(UPSTREAM + path, { method, headers, body });
  const text = await r.text();
  res.writeHead(r.status, { 'content-type': r.headers.get('content-type') || 'application/json' });
  res.end(text);
  return { status: r.status, text };
}

// ------------------------------------------------------------ routes
const server = http.createServer(async (req, res) => {
  try {
    const url = new URL(req.url, 'http://localhost');
    const p = url.pathname;

    if (p === '/health') return send(res, 200, { ok: true, models: [...ALLOWED_MODELS] });

    if (!p.startsWith('/replicate/v1/')) return send(res, 404, { detail: 'Not found' });
    if (!TOKEN) return send(res, 500, { detail: 'Server is missing REPLICATE_API_TOKEN' });
    if (APP_KEY && req.headers['x-app-key'] !== APP_KEY) {
      return send(res, 401, { detail: 'Unauthorized' });
    }
    const ip = (req.headers['x-forwarded-for'] || req.socket.remoteAddress || '')
      .toString().split(',')[0].trim();
    // Only job-creating calls count; status polling is free.
    if (req.method === 'POST' && rateLimited(ip)) {
      return send(res, 429, { detail: 'Too many requests' });
    }

    const rest = p.slice('/replicate'.length); // "/v1/..."
    let m;

    // GET /v1/models/{owner}/{name}
    if (req.method === 'GET' && (m = rest.match(/^\/v1\/models\/([^/]+)\/([^/]+)$/))) {
      const slug = `${m[1]}/${m[2]}`;
      if (!ALLOWED_MODELS.has(slug)) return send(res, 403, { detail: 'Model not allowed' });
      const { status, text } = await forward(res, 'GET', rest);
      if (status === 200) {
        try {
          const id = JSON.parse(text)?.latest_version?.id;
          if (id) allowedVersions.add(id);
        } catch (_) {}
      }
      return;
    }

    // POST /v1/models/{owner}/{name}/predictions
    if (req.method === 'POST' && (m = rest.match(/^\/v1\/models\/([^/]+)\/([^/]+)\/predictions$/))) {
      const slug = `${m[1]}/${m[2]}`;
      if (!ALLOWED_MODELS.has(slug)) return send(res, 403, { detail: 'Model not allowed' });
      const body = await readBody(req, 1024 * 1024);
      return forward(res, 'POST', rest, { body, contentType: 'application/json' });
    }

    // POST /v1/predictions  (community models, by version id)
    if (req.method === 'POST' && rest === '/v1/predictions') {
      const body = await readBody(req, 1024 * 1024);
      let json;
      try { json = JSON.parse(body.toString('utf8')); } catch (_) {
        return send(res, 400, { detail: 'Invalid JSON' });
      }
      if (!allowedVersions.has(json.version)) {
        return send(res, 403, { detail: 'Version not allowed' });
      }
      return forward(res, 'POST', rest, { body, contentType: 'application/json' });
    }

    // GET /v1/predictions/{id}
    if (req.method === 'GET' && /^\/v1\/predictions\/[A-Za-z0-9_-]+$/.test(rest)) {
      return forward(res, 'GET', rest);
    }

    // POST /v1/files  (multipart upload, streamed through)
    if (req.method === 'POST' && rest === '/v1/files') {
      const len = Number(req.headers['content-length'] || 0);
      if (len > MAX_UPLOAD) return send(res, 413, { detail: 'File too large' });
      const body = await readBody(req, MAX_UPLOAD);
      return forward(res, 'POST', rest, {
        body,
        contentType: req.headers['content-type'],
      });
    }

    return send(res, 404, { detail: 'Not found' });
  } catch (e) {
    const status = e.status || 502;
    if (!res.headersSent) send(res, status, { detail: e.message || 'Proxy error' });
    else res.end();
  }
});

if (require.main === module) {
  server.listen(PORT, () => {
    console.log(`Enhancify proxy listening on :${PORT}`);
    if (!TOKEN) console.warn('WARNING: REPLICATE_API_TOKEN is not set');
    if (!APP_KEY) console.warn('WARNING: APP_KEY is not set; anyone can use this proxy');
  });
}

module.exports = { server };
