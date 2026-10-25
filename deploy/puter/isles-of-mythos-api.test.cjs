const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const path = require('node:path');
const routes = new Map();
const router = {
  get: (p, fn) => routes.set('GET '+p, fn),
  post: (p, fn) => routes.set('POST '+p, fn),
};
let networkCalls = 0;
vm.runInNewContext(fs.readFileSync(path.join(__dirname,'isles-of-mythos-api.js'),'utf8'), {
  router, Response, URL, AbortSignal,
  fetch: () => { networkCalls++; throw Error('Fail closed'); }
});
(async () => {
  const health = routes.get('GET /health')();
  assert.equal(health.status, 'ok');
  assert.equal(health.version, '0.3.0');
  assert.equal(health.authBackendConfigured, false);
  for (const route of ['/auth/register','/auth/login','/auth/admin/login']) {
    const res = await routes.get('POST '+route)({
      request:new Request('https://local.invalid'+route,{
        method:'POST',headers:{'content-type':'application/json'},body:'{}'
      })
    });
    assert.equal(res.status,503);
    assert.equal((await res.json()).error,'AUTH_BACKEND_UNAVAILABLE');
  }
  for (const route of ['/auth/me','/auth/admin/me']) {
    const res = await routes.get('GET '+route)({
      request:new Request('https://local.invalid'+route,{headers:{authorization:'Bearer test'}})
    });
    assert.equal(res.status,503);
  }
  assert.equal(networkCalls,0);
  assert.equal(routes.size,7);
  console.log('PASS: health and five fail-closed auth routes');
})().catch(error=>{console.error(error);process.exitCode=1});
