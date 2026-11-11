/** Service-role calls to the admin_* functions (design.md). */
export interface DbEnv {
  SUPABASE_URL: string;
  SUPABASE_SERVICE_ROLE_KEY: string;
}

export class DbError extends Error {
  constructor(readonly status: number, readonly hint: string | null, message: string) {
    super(message);
  }
}

export function configured(env: DbEnv): boolean {
  const url = env.SUPABASE_URL ?? '';
  return !!url && !url.includes('YOUR-PROJECT-REF') && !!env.SUPABASE_SERVICE_ROLE_KEY;
}

export async function rpc<T>(env: DbEnv, fn: string, params: Record<string, unknown> = {}): Promise<T> {
  const key = env.SUPABASE_SERVICE_ROLE_KEY;
  const headers: Record<string, string> = { apikey: key, 'content-type': 'application/json' };
  // Legacy JWT keys also go in Authorization; new sb_secret_ keys are not JWTs.
  if (!key.startsWith('sb_')) headers.authorization = `Bearer ${key}`;
  const res = await fetch(`${env.SUPABASE_URL.replace(/\/+$/, '')}/rest/v1/rpc/${fn}`, {
    method: 'POST',
    headers,
    body: JSON.stringify(params),
  });
  if (!res.ok) {
    const body = (await res.json().catch(() => ({}))) as { message?: string; hint?: string };
    throw new DbError(res.status, body.hint ?? null, body.message ?? `${fn} failed (${res.status})`);
  }
  return (await res.json()) as T;
}

export interface Stats {
  pending_count: number;
  oldest_pending_at: string | null;
  reported_count: number;
  oldest_report_at: string | null;
}

export interface QueueRow {
  id: string;
  author_id: string;
  status: string;
  post_kind: string;
  locality: string | null;
  country_code: string | null;
  captured_on: string | null;
  image_key: string;
  thumb_key: string;
  created_at: string;
  published_at: string | null;
  author_nickname: string | null;
  author_approved: number;
  author_hidden: number;
  author_banned: boolean;
  open_reports: number;
  report_reasons: string[];
  first_report_at: string | null;
}

export interface ReportRow {
  reason: string;
  note: string | null;
  created_at: string;
  resolved_at: string | null;
  resolution: string | null;
}

export interface LogRow {
  at: string;
  actor: string;
  action: string;
  post_id: string | null;
  user_id: string | null;
  note: string | null;
}
