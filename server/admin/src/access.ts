/**
 * Cloudflare Access in front of the console identifies the operator; this checks its signed
 * assertion on every request (design.md). Missing configuration refuses everyone.
 */
export interface AccessEnv {
  ACCESS_TEAM_DOMAIN: string;
  ACCESS_AUD: string;
  ALLOWED_EMAILS: string;
}

export class AccessError extends Error {
  constructor(readonly status: 401 | 403 | 503, message: string) {
    super(message);
  }
}

type Jwk = JsonWebKey & { kid?: string };
type FetchLike = (url: string) => Promise<Response>;

const certCache = new Map<string, { at: number; keys: Jwk[] }>();
const CERT_TTL_MS = 60 * 60 * 1000;

export function _resetCertCache(): void {
  certCache.clear();
}

function b64urlToBytes(s: string): Uint8Array {
  const b64 = s.replace(/-/g, '+').replace(/_/g, '/') + '='.repeat((4 - (s.length % 4)) % 4);
  const bin = atob(b64);
  const out = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
  return out;
}

function decodeJson(part: string): Record<string, unknown> {
  return JSON.parse(new TextDecoder().decode(b64urlToBytes(part))) as Record<string, unknown>;
}

async function certs(team: string, fetcher: FetchLike, refresh = false): Promise<Jwk[]> {
  const hit = certCache.get(team);
  if (!refresh && hit && Date.now() - hit.at < CERT_TTL_MS) return hit.keys;
  const res = await fetcher(`https://${team}/cdn-cgi/access/certs`);
  if (!res.ok) throw new AccessError(503, 'Could not load the Access signing keys.');
  const body = (await res.json()) as { keys?: Jwk[] };
  const keys = body.keys ?? [];
  certCache.set(team, { at: Date.now(), keys });
  return keys;
}

function assertion(request: Request): string | null {
  const header = request.headers.get('cf-access-jwt-assertion');
  if (header) return header;
  const cookie = request.headers.get('cookie') ?? '';
  const m = /(?:^|;\s*)CF_Authorization=([^;]+)/.exec(cookie);
  return m?.[1] ?? null;
}

/** Returns the operator's email, or throws AccessError. */
export async function verifyAccess(request: Request, env: AccessEnv, fetcher: FetchLike = (u) => fetch(u),
                                   now: () => number = () => Date.now()): Promise<string> {
  const team = env.ACCESS_TEAM_DOMAIN?.trim();
  const aud = env.ACCESS_AUD?.trim();
  const allowed = (env.ALLOWED_EMAILS ?? '').split(',').map((e) => e.trim().toLowerCase()).filter(Boolean);
  if (!team || !aud || allowed.length === 0) throw new AccessError(503, 'The console is not configured yet.');

  const token = assertion(request);
  if (!token) throw new AccessError(401, 'Sign in through Cloudflare Access.');
  const parts = token.split('.');
  if (parts.length !== 3) throw new AccessError(401, 'Malformed Access token.');
  const [h, p, s] = parts as [string, string, string];

  let header: Record<string, unknown>, payload: Record<string, unknown>;
  try {
    header = decodeJson(h);
    payload = decodeJson(p);
  } catch {
    throw new AccessError(401, 'Malformed Access token.');
  }
  if (header.alg !== 'RS256') throw new AccessError(401, 'Unexpected token algorithm.');

  let keys = await certs(team, fetcher);
  let jwk = keys.find((k) => k.kid === header.kid);
  if (!jwk) {
    keys = await certs(team, fetcher, true); // keys rotated
    jwk = keys.find((k) => k.kid === header.kid);
  }
  if (!jwk) throw new AccessError(401, 'Unknown signing key.');

  const key = await crypto.subtle.importKey('jwk', jwk, { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' }, false, ['verify']);
  const ok = await crypto.subtle.verify('RSASSA-PKCS1-v1_5', key, b64urlToBytes(s), new TextEncoder().encode(`${h}.${p}`));
  if (!ok) throw new AccessError(401, 'Invalid token signature.');

  const seconds = now() / 1000;
  if (typeof payload.exp !== 'number' || payload.exp < seconds) throw new AccessError(401, 'Access session expired.');
  if (typeof payload.nbf === 'number' && payload.nbf > seconds + 60) throw new AccessError(401, 'Token not valid yet.');
  if (payload.iss !== `https://${team}`) throw new AccessError(401, 'Unexpected token issuer.');
  const auds = Array.isArray(payload.aud) ? payload.aud : [payload.aud];
  if (!auds.includes(aud)) throw new AccessError(403, 'This token is for another application.');

  const email = typeof payload.email === 'string' ? payload.email.toLowerCase() : '';
  if (!email || !allowed.includes(email)) throw new AccessError(403, 'This account is not an operator.');
  return email;
}
