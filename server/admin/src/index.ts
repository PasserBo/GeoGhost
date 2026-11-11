import { AccessError, verifyAccess, type AccessEnv } from './access';
import { configured, DbError, rpc, type DbEnv, type LogRow, type QueueRow, type ReportRow, type Stats } from './db';
import { log, message, page, queue, type Tab } from './html';

export interface Env extends AccessEnv, DbEnv {
  POSTS: R2Bucket;
}

const SECURITY_HEADERS = {
  'content-security-policy': "default-src 'none'; img-src 'self'; style-src 'unsafe-inline'; script-src 'unsafe-inline'; form-action 'self'; frame-ancestors 'none'; base-uri 'none'",
  'x-content-type-options': 'nosniff',
  'referrer-policy': 'no-referrer',
  'cache-control': 'no-store',
};

function html(body: string, status = 200): Response {
  return new Response(body, { status, headers: { 'content-type': 'text/html; charset=utf-8', ...SECURITY_HEADERS } });
}

const FLASH: Record<string, string> = { approve: '已通过', reject: '已拒绝', remove: '已删除', ban: '已封禁', unban: '已解除封禁' };

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    let actor: string;
    try {
      if (!configured(env)) throw new AccessError(503, 'The console is not configured yet.');
      actor = await verifyAccess(request, env);
    } catch (e) {
      if (e instanceof AccessError) return html(message(e.status, e.message), e.status);
      throw e;
    }

    const url = new URL(request.url);
    try {
      if (request.method === 'GET' && url.pathname.startsWith('/img/')) return await image(url, env);
      if (request.method === 'POST' && url.pathname === '/action') return await action(request, url, env, actor);
      if (request.method === 'GET' && url.pathname === '/') return await dashboard(url, env, actor);
      return html(message(404, 'Not found.'), 404);
    } catch (e) {
      if (e instanceof DbError) {
        console.error(`db ${e.status} ${e.hint ?? ''} ${e.message}`);
        return html(message(502, `数据库返回错误：${e.hint ?? e.message}`), 502);
      }
      throw e;
    }
  },
};

async function image(url: URL, env: Env): Promise<Response> {
  const key = decodeURIComponent(url.pathname.slice('/img/'.length));
  if (!/^posts\/[0-9a-f-]{36}\/(full|thumb)\.heic$/.test(key)) return html(message(404, 'Not found.'), 404);
  const object = await env.POSTS.get(key);
  if (!object) return html(message(404, 'Image not found.'), 404);
  return new Response(object.body, {
    headers: { 'content-type': 'image/heic', 'cache-control': 'private, max-age=3600', 'x-content-type-options': 'nosniff' },
  });
}

function tabOf(value: string | null): Tab {
  return value === 'reported' || value === 'log' ? value : 'pending';
}

async function dashboard(url: URL, env: Env, actor: string): Promise<Response> {
  const tab = tabOf(url.searchParams.get('tab'));
  const stats = await rpc<Stats>(env, 'admin_stats');
  let body: string;
  if (tab === 'log') {
    body = log(await rpc<LogRow[]>(env, 'admin_log', { max_rows: 100 }));
  } else {
    const rows = await rpc<QueueRow[]>(env, 'admin_queue', { kind: tab, max_rows: 50 });
    const reports = new Map<string, ReportRow[]>();
    if (tab === 'reported') {
      await Promise.all(rows.map(async (row) => {
        reports.set(row.id, await rpc<ReportRow[]>(env, 'admin_post_reports', { post_id: row.id }));
      }));
    }
    body = queue(tab, rows, reports);
  }
  const done = url.searchParams.get('done');
  return html(page({ tab, stats, actor, body, flash: done ? FLASH[done] ?? null : null }));
}

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

async function action(request: Request, url: URL, env: Env, actor: string): Promise<Response> {
  // Same-origin form posts only.
  if (request.headers.get('origin') !== url.origin) return html(message(403, 'Cross-site request refused.'), 403);
  const form = await request.formData();
  const kind = String(form.get('action') ?? '');
  const tab = tabOf(String(form.get('tab') ?? ''));
  const postID = String(form.get('post_id') ?? '');
  const userID = String(form.get('user_id') ?? '');

  switch (kind) {
    case 'approve':
    case 'reject':
      if (!UUID.test(postID)) return html(message(400, 'Missing post.'), 400);
      await rpc(env, 'admin_moderate', { post_id: postID, decision: kind, actor });
      break;
    case 'remove': {
      if (!UUID.test(postID)) return html(message(400, 'Missing post.'), 400);
      // Mark it removed first, so it disappears even if deleting an image fails.
      const removed = await rpc<{ image_key: string; thumb_key: string }>(env, 'admin_remove_post', { post_id: postID, actor });
      await env.POSTS.delete([removed.image_key, removed.thumb_key]);
      break;
    }
    case 'ban':
    case 'unban':
      if (!UUID.test(userID)) return html(message(400, 'Missing user.'), 400);
      await rpc(env, 'admin_set_ban', { user_id: userID, banned: kind === 'ban', actor });
      break;
    default:
      return html(message(400, 'Unknown action.'), 400);
  }
  return new Response(null, { status: 303, headers: { location: `/?tab=${tab}&done=${kind}`, ...SECURITY_HEADERS } });
}
