import { ApiError } from './http';

/** design.md §7 limits. */
export const FULL_MAX_BYTES = 1.5 * 1024 * 1024; // 1.5 MiB
export const THUMB_MAX_BYTES = 300 * 1024; // 300 KiB
/** Whole request body: both images + multipart overhead. */
export const BODY_MAX_BYTES = FULL_MAX_BYTES + THUMB_MAX_BYTES + 64 * 1024;

const HEIC_BRANDS = new Set(['heic', 'heix', 'mif1']);

/**
 * HEIC check by the ISO-BMFF `ftyp` box: bytes 4..8 are "ftyp" and the major
 * brand (bytes 8..12) is one of heic / heix / mif1.
 */
export function isHeic(bytes: Uint8Array): boolean {
  if (bytes.length < 16) return false;
  const boxSize = ((bytes[0]! << 24) | (bytes[1]! << 16) | (bytes[2]! << 8) | bytes[3]!) >>> 0;
  if (boxSize !== 0 && boxSize !== 1 && boxSize < 16) return false;
  if (ascii(bytes, 4, 8) !== 'ftyp') return false;
  return HEIC_BRANDS.has(ascii(bytes, 8, 12));
}

function ascii(bytes: Uint8Array, start: number, end: number): string {
  let s = '';
  for (let i = start; i < end; i++) s += String.fromCharCode(bytes[i]!);
  return s;
}

export interface UploadedImages {
  full: Uint8Array;
  thumb: Uint8Array;
}

/** Reads, parses and validates the `full` + `thumb` multipart upload. */
export async function readImages(request: Request): Promise<UploadedImages> {
  const boundary = multipartBoundary(request.headers.get('content-type'));
  if (!boundary) {
    throw new ApiError(415, 'unsupported_media_type', 'Expected multipart/form-data.');
  }
  const body = await readBodyCapped(request, BODY_MAX_BYTES);
  const parts = parseMultipart(body, boundary);

  const full = parts.get('full');
  const thumb = parts.get('thumb');
  if (!full || !thumb) {
    throw new ApiError(400, 'bad_request', 'Both "full" and "thumb" parts are required.');
  }
  if (full.length > FULL_MAX_BYTES) {
    throw new ApiError(413, 'too_large', '"full" must be at most 1.5 MB.');
  }
  if (thumb.length > THUMB_MAX_BYTES) {
    throw new ApiError(413, 'too_large', '"thumb" must be at most 300 KB.');
  }
  if (!isHeic(full) || !isHeic(thumb)) {
    throw new ApiError(415, 'unsupported_media_type', 'Images must be HEIC.');
  }
  return { full, thumb };
}

export function multipartBoundary(contentType: string | null): string | null {
  if (!contentType) return null;
  const [type, ...params] = contentType.split(';');
  if (type?.trim().toLowerCase() !== 'multipart/form-data') return null;
  for (const param of params) {
    const eq = param.indexOf('=');
    if (eq < 0) continue;
    if (param.slice(0, eq).trim().toLowerCase() !== 'boundary') continue;
    let value = param.slice(eq + 1).trim();
    if (value.startsWith('"') && value.endsWith('"') && value.length >= 2) value = value.slice(1, -1);
    return value.length > 0 && value.length <= 200 ? value : null;
  }
  return null;
}

export async function readBodyCapped(request: Request, max: number): Promise<Uint8Array> {
  const declared = request.headers.get('content-length');
  if (declared !== null && Number(declared) > max) {
    throw new ApiError(413, 'too_large', 'Request body too large.');
  }
  if (!request.body) throw new ApiError(400, 'bad_request', 'Empty body.');

  const reader = request.body.getReader();
  const chunks: Uint8Array[] = [];
  let total = 0;
  for (;;) {
    const { done, value } = await reader.read();
    if (done) break;
    total += value.byteLength;
    if (total > max) {
      await reader.cancel();
      throw new ApiError(413, 'too_large', 'Request body too large.');
    }
    chunks.push(value);
  }
  const out = new Uint8Array(total);
  let offset = 0;
  for (const c of chunks) {
    out.set(c, offset);
    offset += c.byteLength;
  }
  return out;
}

const encoder = new TextEncoder();
const decoder = new TextDecoder();

/**
 * Binary-safe multipart/form-data parser (RFC 7578). Unlike Request.formData()
 * it does not depend on a `filename` parameter to keep a part as bytes.
 * Returns part name -> bytes; the first part with a given name wins.
 */
export function parseMultipart(body: Uint8Array, boundary: string): Map<string, Uint8Array> {
  const bad = () => new ApiError(400, 'bad_request', 'Malformed multipart body.');
  const delimiter = encoder.encode(`--${boundary}`);
  const nextDelimiter = encoder.encode(`\r\n--${boundary}`);
  const headerEnd = encoder.encode('\r\n\r\n');
  const parts = new Map<string, Uint8Array>();

  let pos = indexOf(body, delimiter, 0);
  if (pos < 0) throw bad();
  pos += delimiter.length;

  for (;;) {
    // After a delimiter: "--" closes the body, otherwise CRLF starts a part.
    if (body[pos] === 0x2d && body[pos + 1] === 0x2d) return parts;
    while (body[pos] === 0x20 || body[pos] === 0x09) pos++; // transport padding
    if (body[pos] !== 0x0d || body[pos + 1] !== 0x0a) throw bad();
    pos += 2;

    const hEnd = indexOf(body, headerEnd, pos);
    if (hEnd < 0) throw bad();
    const headers = decoder.decode(body.subarray(pos, hEnd));
    const contentStart = hEnd + headerEnd.length;
    const contentEnd = indexOf(body, nextDelimiter, contentStart);
    if (contentEnd < 0) throw bad();

    const name = partName(headers);
    if (name !== null && !parts.has(name)) {
      parts.set(name, body.slice(contentStart, contentEnd));
    }
    pos = contentEnd + nextDelimiter.length;
  }
}

function partName(headers: string): string | null {
  for (const line of headers.split('\r\n')) {
    const colon = line.indexOf(':');
    if (colon < 0) continue;
    if (line.slice(0, colon).trim().toLowerCase() !== 'content-disposition') continue;
    const m = /;\s*name\s*=\s*(?:"([^"]*)"|([^;\s]+))/i.exec(line.slice(colon + 1));
    if (m) return m[1] ?? m[2] ?? null;
  }
  return null;
}

function indexOf(haystack: Uint8Array, needle: Uint8Array, from: number): number {
  const first = needle[0];
  const last = haystack.length - needle.length;
  outer: for (let i = Math.max(0, from); i <= last; i++) {
    if (haystack[i] !== first) continue;
    for (let j = 1; j < needle.length; j++) {
      if (haystack[i + j] !== needle[j]) continue outer;
    }
    return i;
  }
  return -1;
}
