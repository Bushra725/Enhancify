// Local test with a fake Workers AI binding: node test.mjs
import assert from 'node:assert';
import { handle } from './worker.js';

let seen;
const env = {
  APP_KEY: 'secret',
  AI: {
    async run(model, opts) {
      const form = await new Response(opts.multipart.body, {
        headers: { 'content-type': opts.multipart.contentType },
      }).formData();
      seen = { model, prompt: form.get('prompt'), w: form.get('width'), h: form.get('height'),
               img: await form.get('input_image_0').text(),
               img1: form.get('input_image_1') ? await form.get('input_image_1').text() : null,
               type0: form.get('input_image_0').type };
      if (seen.prompt === 'boom') throw new Error('4006: you have used up your daily free allocation of 10,000 neurons');
      return { image: 'QUJD' };
    },
  },
};
const call = (fields, key = 'secret') => {
  const fd = new FormData();
  for (const [k, v] of Object.entries(fields)) {
    for (const x of Array.isArray(v) ? v : [v]) fd.append(k, x);
  }
  return handle(new Request('https://w/v1/edit', { method: 'POST', body: fd, headers: { 'x-app-key': key } }), env);
};
const img = new Blob(['PNGDATA'], { type: 'image/png' });

let r = await call({ image: img, prompt: 'x' }, 'wrong'); assert.equal(r.status, 401);
r = await call({ prompt: 'x' }); assert.equal(r.status, 400);
r = await call({ image: img, prompt: 'restore', width: '1000', height: '5000' });
assert.equal(r.status, 200); assert.equal((await r.json()).image, 'QUJD');
assert.equal(seen.model, '@cf/black-forest-labs/flux-2-klein-4b');
assert.equal(seen.img, 'PNGDATA'); assert.equal(seen.w, '992'); assert.equal(seen.h, '1024');
assert.equal(seen.type0, 'image/png'); assert.equal(seen.img1, null);
r = await call({ image: [img, new Blob(['SECOND'], { type: 'image/jpeg' })], prompt: 'two' });
assert.equal(r.status, 200); assert.equal(seen.img1, 'SECOND');
r = await call({ image: img, prompt: 'boom' }); assert.equal(r.status, 503);
r = await handle(new Request('https://w/health'), env); assert.equal(r.status, 200);
console.log('All worker tests passed.');
