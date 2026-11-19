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

function serviceHeaders(env: DbEnv): Record<string, string> {
  const key = env.SUPABASE_SERVICE_ROLE_KEY;
  const headers: Record<string, string> = { apikey: key, 'content-type': 'application/json' };
  // Legacy JWT keys also go in Authorization; new sb_secret_ keys are not JWTs.
  if (!key.startsWith('sb_')) headers.authorization = `Bearer ${key}`;
  return headers;
}

async function checked<T>(res: Response, what: string): Promise<T> {
  if (!res.ok) {
    const body = (await res.json().catch(() => ({}))) as { message?: string; hint?: string };
    throw new DbError(res.status, body.hint ?? null, body.message ?? `${what} failed (${res.status})`);
  }
  return (await res.json()) as T;
}

export async function rpc<T>(env: DbEnv, fn: string, params: Record<string, unknown> = {}): Promise<T> {
  const res = await fetch(`${env.SUPABASE_URL.replace(/\/+$/, '')}/rest/v1/rpc/${fn}`, {
    method: 'POST',
    headers: serviceHeaders(env),
    body: JSON.stringify(params),
  });
  return checked<T>(res, fn);
}

/** The operator settings row (public.app_config, add-update-gate-and-switches). */
export async function getAppConfig(env: DbEnv): Promise<AppConfig> {
  const res = await fetch(`${env.SUPABASE_URL.replace(/\/+$/, '')}/rest/v1/app_config?select=*`, { headers: serviceHeaders(env) });
  const rows = await checked<AppConfig[]>(res, 'app_config');
  if (!rows[0]) throw new DbError(500, null, 'app_config has no row');
  return rows[0];
}

export type NoticeLanguage = 'en' | 'ja' | 'zh-Hans';

export interface AppConfig {
  min_online_version: string;
  latest_version: string;
  publishing_enabled: boolean;
  signups_enabled: boolean;
  notice: Partial<Record<NoticeLanguage, string>> | null;
  updated_at: string;
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
