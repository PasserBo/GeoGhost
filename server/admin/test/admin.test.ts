import { afterEach, beforeAll, describe, expect, it, vi } from 'vitest';
import { _resetCertCache, AccessError, verifyAccess } from '../src/access';
import { esc, log, queue, waited } from '../src/html';
import worker, { type Env } from '../src/index';
import type { QueueRow } from '../src/db';

const TEAM = 'team.cloudflareaccess.com';
const AUD = 'aud-123';
const accessEnv = { ACCESS_TEAM_DOMAIN: TEAM, ACCESS_AUD: AUD, ALLOWED_EMAILS: 'op@example.com, second@example.com' };

let keyPair: CryptoKeyPair;
let publicJwk: JsonWebKey & { kid: string };

function b64url(data: Uint8Array | string): string {
  const bytes = typeof data === 'string' ? new TextEncoder().encode(data) : data;
  let bin = '';
  for (const b of bytes) bin += String.fromCharCode(b);
  return btoa(bin).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

async function sign(payload: Record<string, unknown>, kid = 'k1', key = keyPair.privateKey): Promise<string> {
  const h = b64url(JSON.stringify({ alg: 'RS256', kid, typ: 'JWT' }));
  const p = b64url(JSON.stringify(payload));
  const sig = await crypto.subtle.sign('RSASSA-PKCS1-v1_5', key, new TextEncoder().encode(`${h}.${p}`));
  return `${h}.${p}.${b64url(new Uint8Array(sig))}`;
}

const valid = () => ({ aud: [AUD], iss: `https://${TEAM}`, email: 'OP@example.com', exp: Math.floor(Date.now() / 1000) + 600 });
const certsFetch = async () => new Response(JSON.stringify({ keys: [publicJwk] }));
const req = (token?: string, init: RequestInit = {}, path = '/') =>
  new Request(`https://admin.test${path}`, { ...init, headers: { ...(token ? { 'cf-access-jwt-assertion': token } : {}), ...(init.headers ?? {}) } });

beforeAll(async () => {
  keyPair = (await crypto.subtle.generateKey(
    { name: 'RSASSA-PKCS1-v1_5', modulusLength: 2048, publicExponent: new Uint8Array([1, 0, 1]), hash: 'SHA-256' },
    true, ['sign', 'verify'])) as CryptoKeyPair;
  publicJwk = { ...(await crypto.subtle.exportKey('jwk', keyPair.publicKey) as JsonWebKey), kid: 'k1' };
});

afterEach(() => {
  _resetCertCache();
  vi.unstubAllGlobals();
});

async function rejects(p: Promise<unknown>, status: number) {
  await expect(p).rejects.toSatisfy((e: unknown) => e instanceof AccessError && e.status === status);
}

describe('verifyAccess', () => {
  it('returns the operator email for a valid token', async () => {
    expect(await verifyAccess(req(await sign(valid())), accessEnv, certsFetch)).toBe('op@example.com');
  });

  it('also reads the CF_Authorization cookie', async () => {
    const r = new Request('https://admin.test/', { headers: { cookie: `a=1; CF_Authorization=${await sign(valid())}` } });
    expect(await verifyAccess(r, accessEnv, certsFetch)).toBe('op@example.com');
  });

  it('refuses everyone while unconfigured', async () => {
    await rejects(verifyAccess(req(await sign(valid())), { ...accessEnv, ACCESS_AUD: '' }, certsFetch), 503);
    await rejects(verifyAccess(req(await sign(valid())), { ...accessEnv, ALLOWED_EMAILS: ' ' }, certsFetch), 503);
  });

  it('needs a token', async () => {
    await rejects(verifyAccess(req(), accessEnv, certsFetch), 401);
    await rejects(verifyAccess(req('not.a-jwt'), accessEnv, certsFetch), 401);
  });

  it('rejects expired, foreign and forged tokens', async () => {
    await rejects(verifyAccess(req(await sign({ ...valid(), exp: 1 })), accessEnv, certsFetch), 401);
    await rejects(verifyAccess(req(await sign({ ...valid(), iss: 'https://evil.example' })), accessEnv, certsFetch), 401);
    await rejects(verifyAccess(req(await sign({ ...valid(), aud: ['other'] })), accessEnv, certsFetch), 403);
    const other = (await crypto.subtle.generateKey(
      { name: 'RSASSA-PKCS1-v1_5', modulusLength: 2048, publicExponent: new Uint8Array([1, 0, 1]), hash: 'SHA-256' },
      true, ['sign', 'verify'])) as CryptoKeyPair;
    await rejects(verifyAccess(req(await sign(valid(), 'k1', other.privateKey)), accessEnv, certsFetch), 401);
    await rejects(verifyAccess(req(await sign(valid(), 'unknown-kid')), accessEnv, certsFetch), 401);
  });

  it('only lets listed operators in', async () => {
    await rejects(verifyAccess(req(await sign({ ...valid(), email: 'someone@example.com' })), accessEnv, certsFetch), 403);
  });
});

describe('html', () => {
  it('names config changes in the log', () => {
    const text = log([{ at: '2026-11-19T00:00:00Z', actor: 'op@example.com', action: 'config', post_id: null, user_id: null, note: 'min 1.1.0, latest 1.1.0, publishing paused, signups on, notice none' }]);
    expect(text).toContain('运营设置');
    expect(text).toContain('publishing paused');
  });

  it('escapes user content', () => {
    expect(esc(`<img src=x onerror="alert('x')">`)).toBe('&lt;img src=x onerror=&quot;alert(&#39;x&#39;)&quot;&gt;');
    const row: QueueRow = {
      id: '11111111-1111-1111-1111-111111111111', author_id: '22222222-2222-2222-2222-222222222222', status: 'pending',
      post_kind: 'sticker', locality: '<b>Shibuya</b>', country_code: 'JP', captured_on: '2026-11-12',
      image_key: 'posts/11111111-1111-1111-1111-111111111111/full.heic', thumb_key: 'posts/11111111-1111-1111-1111-111111111111/thumb.heic',
      created_at: new Date(Date.now() - 26 * 3600_000).toISOString(), published_at: null,
      author_nickname: '<script>alert(1)</script>', author_approved: 0, author_hidden: 0, author_banned: false,
      open_reports: 0, report_reasons: [], first_report_at: null,
    };
    const out = queue('pending', [row], new Map());
    expect(out).not.toContain('<script>alert(1)');
    expect(out).toContain('&lt;script&gt;');
    expect(out).not.toContain('<b>Shibuya');
    expect(out).toContain('class="late"');
    expect(out).toContain('data-heic="/img/posts/11111111-1111-1111-1111-111111111111/thumb.heic"');
    // Confirmation lives in admin.js: inline handlers would be blocked by the CSP.
    expect(out).not.toContain('onsubmit');
    expect(out).toContain('data-confirm=');
  });

  it('marks a re-review and counts its wait from the first report', () => {
    const row: QueueRow = {
      id: '11111111-1111-1111-1111-111111111111', author_id: '22222222-2222-2222-2222-222222222222', status: 'pending',
      post_kind: 'sticker', locality: null, country_code: null, captured_on: null,
      image_key: 'posts/11111111-1111-1111-1111-111111111111/full.heic', thumb_key: 'posts/11111111-1111-1111-1111-111111111111/thumb.heic',
      created_at: new Date(Date.now() - 30 * 24 * 3600_000).toISOString(),
      published_at: new Date(Date.now() - 29 * 24 * 3600_000).toISOString(),
      author_nickname: 'a', author_approved: 3, author_hidden: 0, author_banned: false,
      open_reports: 3, report_reasons: ['spam'], first_report_at: new Date(Date.now() - 2 * 3600_000).toISOString(),
    };
    const out = queue('pending', [row], new Map());
    expect(out).toContain('重新审核');
    expect(out).toContain(waited(row.first_report_at).text);
    expect(out).not.toContain(waited(row.created_at).text);
  });

  it('marks waits over 24 hours', () => {
    const now = Date.parse('2026-11-12T12:00:00Z');
    expect(waited('2026-11-11T10:00:00Z', now)).toEqual({ text: '26 小时', late: true });
    expect(waited('2026-11-12T11:30:00Z', now)).toEqual({ text: '30 分钟', late: false });
    expect(waited(null, now).late).toBe(false);
  });
});

describe('worker', () => {
  const env: Env = {
    ...accessEnv,
    SUPABASE_URL: 'https://project.supabase.test',
    SUPABASE_SERVICE_ROLE_KEY: 'sb_secret_test',
    POSTS: { get: vi.fn(async () => null), delete: vi.fn(async () => undefined) } as unknown as R2Bucket,
  };

  function stubNetwork(rpcs: Record<string, unknown> = {}) {
    const calls: { fn: string; body: unknown }[] = [];
    vi.stubGlobal('fetch', vi.fn(async (input: RequestInfo | URL, init?: RequestInit) => {
      const url = String(input);
      if (url.endsWith('/cdn-cgi/access/certs')) return certsFetch();
      const fn = url.split('/rpc/')[1] ?? url.split('/rest/v1/')[1]?.split('?')[0] ?? '';
      calls.push({ fn, body: init?.body ? JSON.parse(String(init.body)) : null });
      return new Response(JSON.stringify(rpcs[fn] ?? {}), { status: 200 });
    }));
    return calls;
  }

  it('refuses without Access', async () => {
    stubNetwork();
    expect((await worker.fetch(req(), env)).status).toBe(401);
    expect((await worker.fetch(req(undefined, {}, '/img/posts/x/thumb.heic'), env)).status).toBe(401);
  });

  it('refuses everyone until Supabase is configured', async () => {
    stubNetwork();
    const r = await worker.fetch(req(await sign(valid())), { ...env, SUPABASE_URL: 'https://YOUR-PROJECT-REF.supabase.co' });
    expect(r.status).toBe(503);
  });

  it('renders the queue for an operator', async () => {
    stubNetwork({ admin_stats: { pending_count: 0, oldest_pending_at: null, reported_count: 0, oldest_report_at: null }, admin_queue: [] });
    const r = await worker.fetch(req(await sign(valid())), env);
    expect(r.status).toBe(200);
    const csp = r.headers.get('content-security-policy') ?? '';
    expect(csp).toContain("frame-ancestors 'none'");
    expect(csp).not.toContain("'unsafe-inline'; script-src 'unsafe-inline'");
    expect(csp).toMatch(/script-src 'self' 'wasm-unsafe-eval'/);
    expect(await r.text()).toContain('没有待审核的帖子');
  });

  it('refuses cross-site actions', async () => {
    const calls = stubNetwork();
    const body = new URLSearchParams({ action: 'approve', post_id: '11111111-1111-1111-1111-111111111111' });
    const r = await worker.fetch(req(await sign(valid()), { method: 'POST', body, headers: { origin: 'https://evil.example' } }, '/action'), env);
    expect(r.status).toBe(403);
    expect(calls.filter((c) => c.fn.startsWith('admin_moderate'))).toHaveLength(0);
  });

  it('accepts a same-origin post whose Origin is null, by Sec-Fetch-Site', async () => {
    stubNetwork({ admin_moderate: { status: 'public' } });
    const body = () => new URLSearchParams({ action: 'approve', post_id: '11111111-1111-1111-1111-111111111111' });
    const token = await sign(valid());
    const ok = await worker.fetch(req(token, { method: 'POST', body: body(), headers: { origin: 'null', 'sec-fetch-site': 'same-origin' } }, '/action'), env);
    expect(ok.status).toBe(303);
    const cross = await worker.fetch(req(token, { method: 'POST', body: body(), headers: { origin: 'null', 'sec-fetch-site': 'cross-site' } }, '/action'), env);
    expect(cross.status).toBe(403);
    const none = await worker.fetch(req(token, { method: 'POST', body: body() }, '/action'), env);
    expect(none.status).toBe(403);
  });

  it('approves with the operator as actor and redirects back', async () => {
    const calls = stubNetwork({ admin_moderate: { status: 'public' } });
    const body = new URLSearchParams({ action: 'approve', tab: 'pending', post_id: '11111111-1111-1111-1111-111111111111' });
    const r = await worker.fetch(req(await sign(valid()), { method: 'POST', body, headers: { origin: 'https://admin.test' } }, '/action'), env);
    expect(r.status).toBe(303);
    expect(r.headers.get('location')).toBe('/?tab=pending&done=approve');
    expect(calls.find((c) => c.fn === 'admin_moderate')?.body).toEqual({
      post_id: '11111111-1111-1111-1111-111111111111', decision: 'approve', actor: 'op@example.com' });
  });

  it('removes the post before deleting its images', async () => {
    const calls = stubNetwork({ admin_remove_post: { image_key: 'posts/a/full.heic', thumb_key: 'posts/a/thumb.heic' } });
    const body = new URLSearchParams({ action: 'remove', post_id: '11111111-1111-1111-1111-111111111111' });
    const r = await worker.fetch(req(await sign(valid()), { method: 'POST', body, headers: { origin: 'https://admin.test' } }, '/action'), env);
    expect(r.status).toBe(303);
    expect(calls[0]?.fn).toBe('admin_remove_post');
    expect(env.POSTS.delete).toHaveBeenCalledWith(['posts/a/full.heic', 'posts/a/thumb.heic']);
  });

  const CONFIG = { min_online_version: '1.1.0', latest_version: '1.2.0', publishing_enabled: false, signups_enabled: true,
    notice: { en: '<b>Maintenance</b> tonight', ja: '今夜メンテナンス' }, updated_at: '2026-11-19T00:00:00Z' };
  const STATS = { pending_count: 0, oldest_pending_at: null, reported_count: 0, oldest_report_at: null };

  it('shows the settings page with the current values, escaped', async () => {
    stubNetwork({ admin_stats: STATS, app_config: [CONFIG] });
    const r = await worker.fetch(req(await sign(valid()), {}, '/?tab=settings'), env);
    expect(r.status).toBe(200);
    const text = await r.text();
    expect(text).toContain('value="1.2.0"');
    expect(text).toContain('&lt;b&gt;Maintenance&lt;/b&gt; tonight');
    expect(text).not.toContain('<b>Maintenance</b>');
    expect(text).toMatch(/name="publishing_enabled" value="on">/);
    expect(text).toMatch(/name="signups_enabled" value="on" checked>/);
    expect(text).toContain('data-confirm=');
    expect(text).not.toMatch(/<script>(?!<)/);
  });

  it('saves settings with the operator as actor; unchecked boxes pause, blank notices are dropped', async () => {
    const calls = stubNetwork({ admin_set_app_config: CONFIG });
    const body = new URLSearchParams({ action: 'config', tab: 'settings', min_online_version: ' 1.1.0 ', latest_version: '1.2.0',
      signups_enabled: 'on', notice_en: 'Hello', notice_ja: '  ', 'notice_zh-Hans': '' });
    const r = await worker.fetch(req(await sign(valid()), { method: 'POST', body, headers: { origin: 'https://admin.test' } }, '/action'), env);
    expect(r.status).toBe(303);
    expect(r.headers.get('location')).toBe('/?tab=settings&done=config');
    expect(calls.find((c) => c.fn === 'admin_set_app_config')?.body).toEqual({
      min_online_version: '1.1.0', latest_version: '1.2.0', publishing_enabled: false, signups_enabled: true,
      notice: { en: 'Hello' }, actor: 'op@example.com' });
  });

  it('refuses cross-site settings changes', async () => {
    const calls = stubNetwork();
    const body = new URLSearchParams({ action: 'config', min_online_version: '9.9.9', latest_version: '9.9.9' });
    const r = await worker.fetch(req(await sign(valid()), { method: 'POST', body, headers: { origin: 'https://evil.example' } }, '/action'), env);
    expect(r.status).toBe(403);
    expect(calls.filter((c) => c.fn === 'admin_set_app_config')).toHaveLength(0);
  });

  it('shows a rejected setting as 400, not as a database outage', async () => {
    vi.stubGlobal('fetch', vi.fn(async (input: RequestInfo | URL) => {
      if (String(input).endsWith('/cdn-cgi/access/certs')) return certsFetch();
      return new Response(JSON.stringify({ hint: 'invalid_argument', message: 'versions must look like 1.2.3' }), { status: 400 });
    }));
    const body = new URLSearchParams({ action: 'config', min_online_version: '1.1', latest_version: '1.1.0' });
    const r = await worker.fetch(req(await sign(valid()), { method: 'POST', body, headers: { origin: 'https://admin.test' } }, '/action'), env);
    expect(r.status).toBe(400);
    expect(await r.text()).toContain('versions must look like 1.2.3');
  });

  it('serves only post images', async () => {
    stubNetwork();
    const token = await sign(valid());
    expect((await worker.fetch(req(token, {}, '/img/secrets/other.txt'), env)).status).toBe(404);
    expect((await worker.fetch(req(token, {}, '/img/posts/11111111-1111-1111-1111-111111111111/thumb.heic'), env)).status).toBe(404);
    expect(env.POSTS.get).toHaveBeenCalledWith('posts/11111111-1111-1111-1111-111111111111/thumb.heic');
  });
});
