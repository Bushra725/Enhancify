// Integration test with a fake Replicate upstream: node test.js
'use strict';
const http = require('http');
const assert = require('assert');

const calls = [];
const upstream = http.createServer((req, res) => {
  let body = '';
  req.on('data', (c) => (body += c));
  req.on('end', () => {
    calls.push({ method: req.method, url: req.url, auth: req.headers.authorization, body });
    res.setHeader('content-type', 'application/json');
    if (req.url === '/v1/models/sczhou/codeformer') return res.end(JSON.stringify({ latest_version: { id: 'abc123' } }));
    if (req.url === '/v1/models/sczhou/codeformer/predictions') { res.statusCode = 404; return res.end('{"detail":"not official"}'); }
    if (req.url === '/v1/predictions') return res.end(JSON.stringify({ id: 'p1', status: 'starting' }));
    if (req.url === '/v1/predictions/p1') return res.end(JSON.stringify({ id: 'p1', status: 'succeeded', output: 'https://x/y.png' }));
    if (req.url === '/v1/files') return res.end(JSON.stringify({ urls: { get: 'https://files/1' } }));
    res.statusCode = 404; res.end('{}');
  });
});

upstream.listen(0, async () => {
  process.env.REPLICATE_BASE = `http://127.0.0.1:${upstream.address().port}`;
  process.env.REPLICATE_API_TOKEN = 'r8_test';
  process.env.APP_KEY = 'secret';
  const { server } = require('./server');
  server.listen(0, async () => {
    const base = `http://127.0.0.1:${server.address().port}/replicate/v1`;
    const h = { 'x-app-key': 'secret' };
    let r;
    r = await fetch(`${base}/models/sczhou/codeformer`); assert.strictEqual(r.status, 401);
    r = await fetch(`${base}/models/evil/model`, { headers: h }); assert.strictEqual(r.status, 403);
    r = await fetch(`${base}/predictions`, { method: 'POST', headers: { ...h, 'content-type': 'application/json' }, body: JSON.stringify({ version: 'abc123', input: {} }) });
    assert.strictEqual(r.status, 403, 'unknown version rejected before model lookup');
    r = await fetch(`${base}/models/sczhou/codeformer`, { headers: h }); assert.strictEqual(r.status, 200);
    r = await fetch(`${base}/models/sczhou/codeformer/predictions`, { method: 'POST', headers: h, body: '{"input":{}}' });
    assert.strictEqual(r.status, 404, 'upstream status passed through');
    r = await fetch(`${base}/predictions`, { method: 'POST', headers: { ...h, 'content-type': 'application/json' }, body: JSON.stringify({ version: 'abc123', input: { image: 'u' } }) });
    assert.strictEqual(r.status, 200); assert.strictEqual((await r.json()).id, 'p1');
    r = await fetch(`${base}/predictions/p1`, { headers: h }); assert.strictEqual((await r.json()).status, 'succeeded');
    const fd = new FormData(); fd.append('content', new Blob(['hello']), 'a.jpg');
    r = await fetch(`${base}/files`, { method: 'POST', headers: h, body: fd });
    assert.strictEqual(r.status, 200); assert.strictEqual((await r.json()).urls.get, 'https://files/1');
    const fileCall = calls.find((c) => c.url === '/v1/files');
    assert.ok(fileCall.body.includes('hello') && fileCall.body.includes('name="content"'));
    assert.ok(calls.every((c) => c.auth === 'Bearer r8_test'), 'token injected upstream');
    r = await fetch(`http://127.0.0.1:${server.address().port}/health`); assert.strictEqual(r.status, 200);
    console.log('All proxy tests passed (' + calls.length + ' upstream calls).');
    server.close(); upstream.close();
  });
});
