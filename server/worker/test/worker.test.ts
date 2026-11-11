import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import worker, { type Env } from '../src/index';
import { FULL_MAX_BYTES } from '../src/upload';
import { ftyp } from './helpers';

const SUPABASE = 'https://test-project.supabase.co';
const API = 'https://api.test';
const ALICE = '00000000-0000-0000-0000-00000000000a';
const BOB = '00000000-0000-0000-0000-00000000000b';
const POST_ID = '11111111-1111-4111-8111-111111111111';

// ---------------------------------------------------------------- fake R2
class MemoryBucket {
  objects = new Map<string, { data: Uint8Array; etag: string; contentType?: string }>();
  async put(key: string, value: Uint8Array, opts?: { httpMetadata?: { contentType?: string } }) {
    this.objects.set(key, { data: value, etag: `"etag-${key}-${value.length}"`, contentType: opts?.httpMetadata?.contentType });
    return {};
  }
  private meta(key: string) {
    const o = this.objects.get(key)!;
    return { key, size: o.data.length, httpEtag: o.etag, httpMetadata: { contentType: o.contentType } };
  }
  async head(key: string) {
    return this.objects.has(key) ? this.meta(key) : null;
  }
  async get(key: string, opts?: { onlyIf?: Headers }) {
    const o = this.objects.get(key);
    if (!o) return null;
    if (opts?.onlyIf?.get('if-none-match') === o.etag) return this.meta(key);
    return { ...this.meta(key), body: new Response(o.data).body };
  }
  async delete(keys: string | string[]) {
    for (const k of Array.isArray(keys) ? keys : [keys]) this.objects.delete(k);
  }
}

// ---------------------------------------------------------------- fake Supabase
interface FakePost {
  id: string;
  author_id: string;
  status: string;
  image_key: string;
  thumb_key: string;
}
let posts: FakePost[];
let banned: Set<string>;
let deletedUsers: string[];
let calls: string[];
let bucket: MemoryBucket;
let env: Env;

function post(id: string, author: string, status: string): FakePost {
  return { id, author_id: author, status, image_key: `posts/${id}/full.heic`, thumb_key: `posts/${id}/thumb.heic` };
}

async function fakeSupabase(input: RequestInfo | URL, init?: RequestInit): Promise<Response> {
  const req = new Request(input as string, init);
  const url = new URL(req.url);
  calls.push(`${req.method} ${url.pathname}${url.search}`);
  const json = (b: unknown, status = 200) => new Response(JSON.stringify(b), { status, headers: { 'content-type': 'application/json' } });

  if (url.pathname === '/auth/v1/user') {
    expect(req.headers.get('apikey')).toBe('anon-key');
    const token = req.headers.get('authorization');
    if (token === 'Bearer alice-token') return json({ id: ALICE });
    if (token === 'Bearer bob-token') return json({ id: BOB });
    return json({ msg: 'invalid JWT' }, 401);
  }
  // everything else must use the service role key
  expect(req.headers.get('apikey')).toBe('service-key');
  expect(req.headers.get('authorization')).toBe('Bearer service-key');

  if (url.pathname === '/rest/v1/posts' && req.method === 'GET') {
    const id = url.searchParams.get('id')?.replace('eq.', '');
    const author = url.searchParams.get('author_id')?.replace('eq.', '');
    return json(posts.filter((p) => (id ? p.id === id : true) && (author ? p.author_id === author : true)));
  }
  if (url.pathname === '/rest/v1/posts' && req.method === 'PATCH') {
    const id = url.searchParams.get('id')!.replace('eq.', '');
    const body = (await req.json()) as { status: string };
    for (const p of posts) if (p.id === id && p.status !== 'removed') p.status = body.status;
    return new Response(null, { status: 204 });
  }
  if (url.pathname === '/rest/v1/rpc/complete_post_upload') {
    const { post_id } = (await req.json()) as { post_id: string };
    const p = posts.find((x) => x.id === post_id);
    if (!p) return json({ code: 'P0002', hint: 'not_found', message: 'post not found' }, 404);
    if (banned.has(p.author_id)) return json({ code: 'P0001', hint: 'banned', message: 'banned' }, 400);
    if (p.status === 'uploading') p.status = 'pending';
    return json({ post_id, status: p.status });
  }
  if (url.pathname.startsWith('/auth/v1/admin/users/') && req.method === 'DELETE') {
    const id = url.pathname.split('/').pop()!;
    deletedUsers.push(id);
    posts = posts.filter((p) => p.author_id !== id);
    return json({});
  }
  return json({ message: 'unexpected' }, 500);
}

beforeEach(() => {
  posts = [post(POST_ID, ALICE, 'uploading')];
  banned = new Set();
  deletedUsers = [];
  calls = [];
  bucket = new MemoryBucket();
  env = {
    POSTS: bucket as unknown as R2Bucket,
    SUPABASE_URL: SUPABASE,
    SUPABASE_ANON_KEY: 'anon-key',
    SUPABASE_SERVICE_ROLE_KEY: 'service-key',
  };
  vi.stubGlobal('fetch', vi.fn(fakeSupabase));
});
afterEach(() => vi.unstubAllGlobals());

// ---------------------------------------------------------------- helpers
const enc = new TextEncoder();
function multipart(parts: Record<string, Uint8Array>, boundary = 'gg-boundary'): { body: Uint8Array; type: string } {
  const chunks: Uint8Array[] = [];
  for (const [name, data] of Object.entries(parts)) {
    chunks.push(enc.encode(`--${boundary}\r\nContent-Disposition: form-data; name="${name}"\r\nContent-Type: image/heic\r\n\r\n`), data, enc.encode('\r\n'));
  }
  chunks.push(enc.encode(`--${boundary}--\r\n`));
  const body = new Uint8Array(chunks.reduce((n, c) => n + c.length, 0));
  let o = 0;
  for (const c of chunks) {
    body.set(c, o);
    o += c.length;
  }
  return { body, type: `multipart/form-data; boundary=${boundary}` };
}

async function call(method: string, path: string, opts: { token?: string; body?: Uint8Array; type?: string; headers?: Record<string, string> } = {}) {
  const headers: Record<string, string> = { ...opts.headers };
  if (opts.token) headers.authorization = `Bearer ${opts.token}`;
  if (opts.type) headers['content-type'] = opts.type;
  const res = await worker.fetch(new Request(`${API}${path}`, { method, headers, body: opts.body }), env);
  const text = await res.text();
  return { status: res.status, headers: res.headers, body: text ? (res.headers.get('content-type')?.includes('json') ? JSON.parse(text) : text) : null };
}

const goodImages = () => multipart({ full: ftyp('heic', ['mif1', 'heic'], 2000), thumb: ftyp('heic', ['mif1', 'heic'], 500) });

// ---------------------------------------------------------------- tests
describe('routing and auth', () => {
  it('unknown path -> 404 JSON', async () => {
    const r = await call('GET', '/nope');
    expect(r.status).toBe(404);
    expect(r.body).toEqual({ error: 'not_found', message: expect.any(String) });
  });
  it('wrong method -> 405 with Allow', async () => {
    const r = await call('POST', `/v1/posts/${POST_ID}/images`);
    expect(r.status).toBe(405);
    expect(r.headers.get('allow')).toBe('PUT');
  });
  it('missing token -> 401', async () => {
    const r = await call('DELETE', '/v1/me');
    expect(r.status).toBe(401);
    expect(r.body.error).toBe('unauthorized');
  });
  it('invalid token -> 401', async () => {
    const r = await call('DELETE', `/v1/posts/${POST_ID}`, { token: 'garbage' });
    expect(r.status).toBe(401);
  });
  it('placeholder configuration -> 500', async () => {
    env.SUPABASE_URL = 'https://YOUR-PROJECT-REF.supabase.co';
    const r = await call('DELETE', '/v1/me', { token: 'alice-token' });
    expect(r.status).toBe(500);
  });
});

describe('PUT /v1/posts/{id}/images', () => {
  it('stores both images and completes the post', async () => {
    const r = await call('PUT', `/v1/posts/${POST_ID}/images`, { token: 'alice-token', ...goodImages() });
    expect(r.status).toBe(200);
    expect(r.body).toEqual({ status: 'pending' });
    expect(bucket.objects.get(`posts/${POST_ID}/full.heic`)?.data.length).toBe(2000);
    expect(bucket.objects.get(`posts/${POST_ID}/thumb.heic`)?.contentType).toBe('image/heic');
    expect(calls).toContain('POST /rest/v1/rpc/complete_post_upload');
  });
  it('retry after completion returns the same status without rewriting images', async () => {
    await call('PUT', `/v1/posts/${POST_ID}/images`, { token: 'alice-token', ...goodImages() });
    const before = bucket.objects.get(`posts/${POST_ID}/full.heic`);
    const again = multipart({ full: ftyp('heic', ['heic'], 3000), thumb: ftyp('heic', ['heic'], 100) });
    const r = await call('PUT', `/v1/posts/${POST_ID}/images`, { token: 'alice-token', ...again });
    expect(r.status).toBe(200);
    expect(r.body).toEqual({ status: 'pending' });
    expect(bucket.objects.get(`posts/${POST_ID}/full.heic`)).toBe(before);
  });
  it('unknown post -> 404', async () => {
    const r = await call('PUT', `/v1/posts/22222222-2222-4222-8222-222222222222/images`, { token: 'alice-token', ...goodImages() });
    expect(r.status).toBe(404);
  });
  it('not the author -> 403', async () => {
    const r = await call('PUT', `/v1/posts/${POST_ID}/images`, { token: 'bob-token', ...goodImages() });
    expect(r.status).toBe(403);
    expect(r.body.error).toBe('forbidden');
  });
  it('removed post -> 409', async () => {
    posts[0]!.status = 'removed';
    const r = await call('PUT', `/v1/posts/${POST_ID}/images`, { token: 'alice-token', ...goodImages() });
    expect(r.status).toBe(409);
    expect(r.body.error).toBe('invalid_status');
  });
  it('not multipart -> 415', async () => {
    const r = await call('PUT', `/v1/posts/${POST_ID}/images`, { token: 'alice-token', body: ftyp('heic'), type: 'image/heic' });
    expect(r.status).toBe(415);
  });
  it('non-HEIC image -> 415', async () => {
    const png = new Uint8Array(100);
    png.set([0x89, 0x50, 0x4e, 0x47]);
    const r = await call('PUT', `/v1/posts/${POST_ID}/images`, { token: 'alice-token', ...multipart({ full: ftyp('heic'), thumb: png }) });
    expect(r.status).toBe(415);
    expect(r.body.error).toBe('unsupported_media_type');
    expect(bucket.objects.size).toBe(0);
  });
  it('AVIF (ftyp avif, compatible mif1) -> 415', async () => {
    const avif = ftyp('avif', ['avif', 'mif1', 'miaf']);
    const r = await call('PUT', `/v1/posts/${POST_ID}/images`, { token: 'alice-token', ...multipart({ full: avif, thumb: ftyp('heic') }) });
    expect(r.status).toBe(415);
  });
  it('full over 1.5 MB -> 413', async () => {
    const r = await call('PUT', `/v1/posts/${POST_ID}/images`, {
      token: 'alice-token',
      ...multipart({ full: ftyp('heic', ['heic'], FULL_MAX_BYTES + 1), thumb: ftyp('heic') }),
    });
    expect(r.status).toBe(413);
  });
  it('thumb over 300 KB -> 413', async () => {
    const r = await call('PUT', `/v1/posts/${POST_ID}/images`, {
      token: 'alice-token',
      ...multipart({ full: ftyp('heic'), thumb: ftyp('heic', ['heic'], 300 * 1024 + 1) }),
    });
    expect(r.status).toBe(413);
  });
  it('whole body far too large -> 413 before parsing', async () => {
    const r = await call('PUT', `/v1/posts/${POST_ID}/images`, {
      token: 'alice-token',
      ...multipart({ full: new Uint8Array(3 * 1024 * 1024), thumb: ftyp('heic') }),
    });
    expect(r.status).toBe(413);
  });
  it('missing part -> 400', async () => {
    const r = await call('PUT', `/v1/posts/${POST_ID}/images`, { token: 'alice-token', ...multipart({ full: ftyp('heic') }) });
    expect(r.status).toBe(400);
  });
  it('banned author -> 403 and uploaded objects are deleted again', async () => {
    banned.add(ALICE);
    const r = await call('PUT', `/v1/posts/${POST_ID}/images`, { token: 'alice-token', ...goodImages() });
    expect(r.status).toBe(403);
    expect(r.body.error).toBe('banned');
    expect(bucket.objects.size).toBe(0);
  });
});

describe('DELETE /v1/posts/{id}', () => {
  it('deletes both images and marks the post removed; repeat is a no-op', async () => {
    posts[0]!.status = 'public';
    await bucket.put(`posts/${POST_ID}/full.heic`, new Uint8Array(1));
    await bucket.put(`posts/${POST_ID}/thumb.heic`, new Uint8Array(1));
    const r = await call('DELETE', `/v1/posts/${POST_ID}`, { token: 'alice-token' });
    expect(r.status).toBe(200);
    expect(r.body).toEqual({ status: 'removed' });
    expect(bucket.objects.size).toBe(0);
    expect(posts[0]!.status).toBe('removed');
    const again = await call('DELETE', `/v1/posts/${POST_ID}`, { token: 'alice-token' });
    expect(again.status).toBe(200);
  });
  it('not the author -> 403', async () => {
    const r = await call('DELETE', `/v1/posts/${POST_ID}`, { token: 'bob-token' });
    expect(r.status).toBe(403);
    expect(posts[0]!.status).toBe('uploading');
  });
});

describe('DELETE /v1/me', () => {
  it('deletes every image of the user and then the auth user', async () => {
    const other = '33333333-3333-4333-8333-333333333333';
    const bobs = '44444444-4444-4444-8444-444444444444';
    posts.push(post(other, ALICE, 'removed'), post(bobs, BOB, 'public'));
    for (const p of posts) {
      await bucket.put(p.image_key, new Uint8Array(1));
      await bucket.put(p.thumb_key, new Uint8Array(1));
    }
    const r = await call('DELETE', '/v1/me', { token: 'alice-token' });
    expect(r.status).toBe(200);
    expect(r.body).toEqual({ ok: true });
    expect([...bucket.objects.keys()].sort()).toEqual([`posts/${bobs}/full.heic`, `posts/${bobs}/thumb.heic`]);
    expect(deletedUsers).toEqual([ALICE]);
  });
});

describe('GET /v1/images/{key}', () => {
  const key = `posts/${POST_ID}/full.heic`;
  it('serves the object with immutable caching', async () => {
    await bucket.put(key, new Uint8Array([1, 2, 3]), { httpMetadata: { contentType: 'image/heic' } });
    const r = await call('GET', `/v1/images/${key}`);
    expect(r.status).toBe(200);
    expect(r.headers.get('cache-control')).toBe('public, max-age=31536000, immutable');
    expect(r.headers.get('content-type')).toBe('image/heic');
    expect(r.headers.get('etag')).toBeTruthy();
  });
  it('If-None-Match -> 304', async () => {
    await bucket.put(key, new Uint8Array([1, 2, 3]));
    const etag = (await bucket.head(key))!.httpEtag;
    const r = await call('GET', `/v1/images/${key}`, { headers: { 'if-none-match': etag } });
    expect(r.status).toBe(304);
  });
  it('missing object -> 404', async () => {
    const r = await call('GET', `/v1/images/${key}`);
    expect(r.status).toBe(404);
    expect(r.body.error).toBe('not_found');
  });
  it('keys outside posts/{uuid}/(full|thumb).heic -> 404', async () => {
    await bucket.put('secret.txt', new Uint8Array(1));
    expect((await call('GET', '/v1/images/secret.txt')).status).toBe(404);
    expect((await call('GET', `/v1/images/posts/${POST_ID}/..%2F..%2Fsecret.txt`)).status).toBe(404);
  });
  it('does not require authentication and does not call Supabase', async () => {
    await bucket.put(key, new Uint8Array([1]));
    await call('GET', `/v1/images/${key}`);
    expect(calls).toEqual([]);
  });
});
