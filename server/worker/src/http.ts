/** Error codes returned in `{"error": "<code>", "message": "..."}` (design.md §7). */
export type ErrorCode =
  | 'bad_request' // 400 malformed request (e.g. missing multipart part)
  | 'unauthorized' // 401 missing / invalid / expired access token
  | 'forbidden' // 403 not the author
  | 'banned' // 403 author is banned
  | 'not_found' // 404
  | 'method_not_allowed' // 405
  | 'invalid_status' // 409 post is not in a state that allows the operation
  | 'too_large' // 413
  | 'update_required' // 426 app version below min_online_version
  | 'unsupported_media_type' // 415 not multipart, or an image that is not HEIC
  | 'internal' // 500
  | 'upstream'; // 502 Supabase / R2 failed

export class ApiError extends Error {
  constructor(
    readonly status: number,
    readonly code: ErrorCode,
    message: string,
  ) {
    super(message);
  }
}

export function json(body: unknown, status = 200, headers: HeadersInit = {}): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'content-type': 'application/json; charset=utf-8', ...headers },
  });
}

export function errorResponse(err: ApiError): Response {
  const headers: Record<string, string> = {};
  if (err.status === 401) headers['www-authenticate'] = 'Bearer';
  return json({ error: err.code, message: err.message }, err.status, headers);
}
