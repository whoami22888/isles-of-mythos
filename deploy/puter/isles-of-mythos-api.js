/* jshint esversion: 11 */
// Isles of Mythos — Puter HTTP auth gateway v0.3.0.
// Infrastructure only: Fastify remains the sole account/token authority.
// Configure after deploying the real TLS-protected Fastify backend.
const UPSTREAM_API_ORIGIN = '';
const VERSION = '0.3.0';
const json = (value, status = 200) => new Response(JSON.stringify(value), {
  status, headers: {'content-type':'application/json; charset=utf-8','cache-control':'no-store'}
});
function upstreamOrigin() {
  if (!UPSTREAM_API_ORIGIN) return null;
  try {
    const url = new URL(UPSTREAM_API_ORIGIN);
    if (url.protocol !== 'https:' || url.username || url.password || url.pathname !== '/' ||
        url.search || url.hash || !url.hostname || url.hostname.endsWith('.example')) return null;
    return url.origin;
  } catch { return null; }
}
async function forward({request}, method, path) {
  const origin = upstreamOrigin();
  if (!origin) return json({error:'AUTH_BACKEND_UNAVAILABLE',message:'Authentication service not configured'},503);
  const headers = {accept:'application/json'};
  let body;
  if (method === 'POST') {
    if (!(request.headers.get('content-type') || '').toLowerCase().startsWith('application/json'))
      return json({error:'UNSUPPORTED_MEDIA_TYPE'},415);
    body = await request.text();
    if (body.length > 8192) return json({error:'PAYLOAD_TOO_LARGE'},413);
    headers['content-type'] = 'application/json';
  } else {
    const bearer = request.headers.get('authorization') || '';
    if (!/^Bearer [A-Za-z0-9._~-]+$/.test(bearer) || bearer.length > 8192)
      return json({error:'UNAUTHORIZED'},401);
    headers.authorization = bearer;
  }
  try {
    const response = await fetch(origin + path, {
      method, headers, body, redirect:'manual', signal:AbortSignal.timeout(8000)
    });
    if (response.status >= 300 && response.status < 400)
      return json({error:'UPSTREAM_REDIRECT_REJECTED'},502);
    if (!(response.headers.get('content-type') || '').toLowerCase().includes('application/json'))
      return json({error:'UPSTREAM_INVALID_RESPONSE'},502);
    const text = await response.text();
    if (text.length > 65536) return json({error:'UPSTREAM_RESPONSE_TOO_LARGE'},502);
    return new Response(text,{status:response.status,headers:{
      'content-type':'application/json; charset=utf-8','cache-control':'no-store'
    }});
  } catch {
    return json({error:'AUTH_BACKEND_UNAVAILABLE'},503);
  }
}
router.get('/', () => ({service:'isles-of-mythos-api',version:VERSION,status:'ok'}));
router.get('/health', () => ({service:'isles-of-mythos-api',version:VERSION,status:'ok',
  authBackendConfigured:!!upstreamOrigin()}));
[
  ['post','/auth/register'],['post','/auth/login'],['post','/auth/admin/login'],
  ['get','/auth/me'],['get','/auth/admin/me']
].forEach(([method, path]) => {
  router[method](path, context => forward(context, method.toUpperCase(), path));
});
