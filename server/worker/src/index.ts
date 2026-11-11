/**
 * GeoGhost online API (docs/spec/changes/setup-online-backend/design.md §7).
 *
 *   PUT    /v1/posts/{post_id}/images   upload full + thumb HEIC, complete the post
 *   DELETE /v1/posts/{post_id}          author retraction
 *   DELETE /v1/me                       delete all my online data
 *   GET    /v1/images/{key}             read an image from R2 (MVP image host)
 */
import { ApiError, errorResponse, json } from './http';
import {
  authenticate,
  completePostUpload,
  deleteAuthUser,
  getPost,
  listUserImageKeys,
  markRemoved,
  type Env,
  type PostRow,
} from './supabase';
import { readImages } from './upload';

export type { Env } from './supabase';

const UUID = '[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}';
const POST_IMAGES = new RegExp(`^/v1/posts/(${UUID})/images$`);
const POST = new RegExp(`^/v1/posts/(${UUID})$`);
const IMAGE_KEY = new RegExp(`^posts/${UUID}/(full|thumb)\\.heic$`);
const R2_DELETE_BATCH = 1000;

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    try {
      return await route(request, env);
    } catch (err) {
      if (err instanceof ApiError) return errorResponse(err);
      console.error('unhandled error', err);
      return errorResponse(new ApiError(500, 'internal', 'Internal error.'));
    }
  },
} satisfies ExportedHandler<Env>;

async function route(request: Request, env: Env): Promise<Response> {
  const { pathname } = new URL(request.url);
  const method = request.method.toUpperCase();
  let m: RegExpExecArray | null;

  if ((m = POST_IMAGES.exec(pathname))) {
    return method === 'PUT' ? uploadImages(request, env, m[1]!.toLowerCase()) : notAllowed('PUT');
  }
  if ((m = POST.exec(pathname))) {
    return method === 'DELETE' ? deletePost(request, env, m[1]!.toLowerCase()) : notAllowed('DELETE');
  }
  if (pathname === '/v1/me') {
    return method === 'DELETE' ? deleteMe(request, env) : notAllowed('DELETE');
  }
  if (pathname.startsWith('/v1/images/')) {
    if (method !== 'GET' && method !== 'HEAD') return notAllowed('GET, HEAD');
    return getImage(request, env, pathname.slice('/v1/images/'.length));
  }
  throw new ApiError(404, 'not_found', 'Not found.');
}

function notAllowed(allow: string): Response {
  const res = errorResponse(new ApiError(405, 'method_not_allowed', 'Method not allowed.'));
  res.headers.set('allow', allow);
  return res;
}

/** Loads the post and checks it belongs to the caller. */
async function ownPost(env: Env, userId: string, postId: string): Promise<PostRow> {
  const post = await getPost(env, postId);
  if (!post) throw new ApiError(404, 'not_found', 'Post not found.');
  if (post.author_id !== userId) throw new ApiError(403, 'forbidden', 'Not the author of this post.');
  return post;
}

// PUT /v1/posts/{post_id}/images
async function uploadImages(request: Request, env: Env, postId: string): Promise<Response> {
  const userId = await authenticate(request, env);
  const post = await ownPost(env, userId, postId);
  if (post.status === 'removed') {
    throw new ApiError(409, 'invalid_status', 'Post was removed.');
  }

  const { full, thumb } = await readImages(request);

  // Already completed (e.g. the response to an earlier attempt was lost):
  // report the current status without touching the stored images, which may
  // already be public and are cached as immutable.
  if (post.status !== 'uploading') return json({ status: post.status });

  const httpMetadata = { contentType: 'image/heic' };
  await Promise.all([
    env.POSTS.put(post.image_key, full, { httpMetadata }),
    env.POSTS.put(post.thumb_key, thumb, { httpMetadata }),
  ]);

  try {
    const status = await completePostUpload(env, postId);
    return json({ status });
  } catch (err) {
    if (err instanceof ApiError && err.code === 'banned') {
      await env.POSTS.delete([post.image_key, post.thumb_key]);
    }
    throw err;
  }
}

// DELETE /v1/posts/{post_id}
async function deletePost(request: Request, env: Env, postId: string): Promise<Response> {
  const userId = await authenticate(request, env);
  const post = await ownPost(env, userId, postId);
  if (post.status !== 'removed') {
    // Images first: if marking fails the client retries and R2 delete is idempotent.
    await env.POSTS.delete([post.image_key, post.thumb_key]);
    await markRemoved(env, postId);
  }
  return json({ status: 'removed' });
}

// DELETE /v1/me
async function deleteMe(request: Request, env: Env): Promise<Response> {
  const userId = await authenticate(request, env);
  const keys = await listUserImageKeys(env, userId);
  for (let i = 0; i < keys.length; i += R2_DELETE_BATCH) {
    await env.POSTS.delete(keys.slice(i, i + R2_DELETE_BATCH));
  }
  await deleteAuthUser(env, userId);
  return json({ ok: true });
}

// GET|HEAD /v1/images/{key}
async function getImage(request: Request, env: Env, rawKey: string): Promise<Response> {
  let key: string;
  try {
    key = decodeURIComponent(rawKey);
  } catch {
    throw new ApiError(404, 'not_found', 'Image not found.');
  }
  if (!IMAGE_KEY.test(key)) throw new ApiError(404, 'not_found', 'Image not found.');

  const object =
    request.method.toUpperCase() === 'HEAD'
      ? await env.POSTS.head(key)
      : await env.POSTS.get(key, { onlyIf: request.headers });
  if (!object) throw new ApiError(404, 'not_found', 'Image not found.');

  const headers = new Headers();
  headers.set('content-type', object.httpMetadata?.contentType ?? 'image/heic');
  headers.set('cache-control', 'public, max-age=31536000, immutable');
  headers.set('etag', object.httpEtag);

  headers.set('content-length', String(object.size));
  if (request.method.toUpperCase() === 'HEAD') return new Response(null, { headers });

  const body = 'body' in object ? (object as R2ObjectBody).body : null;
  if (!body) {
    // Conditional GET whose precondition failed (If-None-Match matched).
    headers.delete('content-length');
    return new Response(null, { status: 304, headers });
  }
  return new Response(body, { headers });
}
