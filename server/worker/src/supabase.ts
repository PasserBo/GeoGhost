import { ApiError } from './http';

export interface Env {
  POSTS: R2Bucket;
  SUPABASE_URL: string;
  SUPABASE_ANON_KEY: string;
  SUPABASE_SERVICE_ROLE_KEY: string;
}

export interface PostRow {
  id: string;
  author_id: string;
  status: 'uploading' | 'pending' | 'public' | 'hidden' | 'removed';
  image_key: string;
  thumb_key: string;
}

function baseUrl(env: Env): string {
  const url = env.SUPABASE_URL?.replace(/\/+$/, '');
  if (!url || url.includes('YOUR-PROJECT-REF') || !env.SUPABASE_ANON_KEY || !env.SUPABASE_SERVICE_ROLE_KEY) {
    throw new ApiError(500, 'internal', 'Worker is not configured.');
  }
  return url;
}

/**
 * Service role headers. Legacy JWT keys go in both `apikey` and
 * `Authorization`; new `sb_secret_…` keys are not JWTs and only go in `apikey`.
 */
function serviceHeaders(env: Env, extra: Record<string, string> = {}): Record<string, string> {
  const key = env.SUPABASE_SERVICE_ROLE_KEY;
  const h: Record<string, string> = { apikey: key, ...extra };
  if (!key.startsWith('sb_')) h.authorization = `Bearer ${key}`;
  return h;
}

async function upstream(res: Response, what: string): Promise<never> {
  const body = await res.text().catch(() => '');
  console.error(`supabase ${what} failed: ${res.status} ${body.slice(0, 500)}`);
  throw new ApiError(502, 'upstream', `Upstream ${what} failed.`);
}

/** Validates the user's access token via GET /auth/v1/user and returns the user id. */
export async function authenticate(request: Request, env: Env): Promise<string> {
  const header = request.headers.get('authorization') ?? '';
  const m = /^Bearer\s+(\S+)$/i.exec(header);
  if (!m) throw new ApiError(401, 'unauthorized', 'Missing bearer token.');
  const url = baseUrl(env);
  const res = await fetch(`${url}/auth/v1/user`, {
    headers: { apikey: env.SUPABASE_ANON_KEY, authorization: `Bearer ${m[1]}` },
  });
  if (res.status === 401 || res.status === 403) {
    throw new ApiError(401, 'unauthorized', 'Invalid or expired token.');
  }
  if (!res.ok) return upstream(res, 'auth');
  const user = (await res.json()) as { id?: unknown };
  if (typeof user.id !== 'string' || user.id.length === 0) {
    throw new ApiError(401, 'unauthorized', 'Invalid token.');
  }
  return user.id;
}

export async function getPost(env: Env, postId: string): Promise<PostRow | null> {
  const url = baseUrl(env);
  const res = await fetch(
    `${url}/rest/v1/posts?id=eq.${encodeURIComponent(postId)}&select=id,author_id,status,image_key,thumb_key`,
    { headers: serviceHeaders(env, { accept: 'application/json' }) },
  );
  if (!res.ok) return upstream(res, 'post lookup');
  const rows = (await res.json()) as PostRow[];
  return rows[0] ?? null;
}

/** Keys of every image the user owns (all posts, any status), paged. */
export async function listUserImageKeys(env: Env, userId: string): Promise<string[]> {
  const url = baseUrl(env);
  const keys: string[] = [];
  const pageSize = 1000;
  for (let offset = 0; ; offset += pageSize) {
    const res = await fetch(
      `${url}/rest/v1/posts?author_id=eq.${encodeURIComponent(userId)}` +
        `&select=id,image_key,thumb_key&order=id&limit=${pageSize}&offset=${offset}`,
      { headers: serviceHeaders(env, { accept: 'application/json' }) },
    );
    if (!res.ok) return upstream(res, 'post listing');
    const rows = (await res.json()) as Pick<PostRow, 'id' | 'image_key' | 'thumb_key'>[];
    for (const r of rows) keys.push(r.image_key, r.thumb_key);
    if (rows.length < pageSize) return keys;
  }
}

interface PostgrestError {
  code?: string;
  hint?: string | null;
  message?: string;
}

/** Service-role RPC complete_post_upload: uploading -> pending / public. */
export async function completePostUpload(env: Env, postId: string): Promise<string> {
  const url = baseUrl(env);
  const res = await fetch(`${url}/rest/v1/rpc/complete_post_upload`, {
    method: 'POST',
    headers: serviceHeaders(env, { 'content-type': 'application/json', accept: 'application/json' }),
    body: JSON.stringify({ post_id: postId }),
  });
  if (res.ok) {
    const out = (await res.json()) as { status?: unknown };
    if (typeof out.status !== 'string') return upstream(res, 'complete_post_upload');
    return out.status;
  }
  const err = (await res
    .clone()
    .json()
    .catch(() => ({}))) as PostgrestError;
  switch (err.hint) {
    case 'banned':
      throw new ApiError(403, 'banned', 'This account is banned.');
    case 'not_found':
      throw new ApiError(404, 'not_found', 'Post not found.');
    case 'invalid_status':
      throw new ApiError(409, 'invalid_status', 'Post can no longer be uploaded.');
  }
  return upstream(res, 'complete_post_upload');
}

/** Author retraction: status -> removed (trigger stamps removed_at). */
export async function markRemoved(env: Env, postId: string): Promise<void> {
  const url = baseUrl(env);
  const res = await fetch(`${url}/rest/v1/posts?id=eq.${encodeURIComponent(postId)}&status=neq.removed`, {
    method: 'PATCH',
    headers: serviceHeaders(env, { 'content-type': 'application/json', prefer: 'return=minimal' }),
    body: JSON.stringify({ status: 'removed' }),
  });
  if (!res.ok) return upstream(res, 'post removal');
}

/** Admin API: deletes the auth user; the database cascades the rest. */
export async function deleteAuthUser(env: Env, userId: string): Promise<void> {
  const url = baseUrl(env);
  const res = await fetch(`${url}/auth/v1/admin/users/${encodeURIComponent(userId)}`, {
    method: 'DELETE',
    headers: serviceHeaders(env),
  });
  if (res.ok || res.status === 404) return;
  return upstream(res, 'user deletion');
}

/** The operator's minimum app version for online features (public.app_config). */
export async function getMinOnlineVersion(env: Env): Promise<string> {
  const url = baseUrl(env);
  const res = await fetch(`${url}/rest/v1/app_config?select=min_online_version`, { headers: serviceHeaders(env) });
  if (!res.ok) return upstream(res, 'app_config');
  const rows = (await res.json()) as { min_online_version?: unknown }[];
  const v = rows[0]?.min_online_version;
  return typeof v === 'string' ? v : '0.0.0';
}
