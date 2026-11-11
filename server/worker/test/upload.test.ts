import { describe, expect, it } from 'vitest';
import { isHeic, multipartBoundary, parseMultipart } from '../src/upload';
import { ApiError } from '../src/http';
import { ftyp } from './helpers';

describe('isHeic', () => {
  it('accepts heic / heix / mif1 major brands', () => {
    expect(isHeic(ftyp('heic'))).toBe(true);
    expect(isHeic(ftyp('heix'))).toBe(true);
    expect(isHeic(ftyp('mif1', ['mif1']))).toBe(true);
  });
  it('rejects other ISO-BMFF brands (avif, mp4)', () => {
    expect(isHeic(ftyp('avif', ['avif', 'mif1', 'miaf']))).toBe(false);
    expect(isHeic(ftyp('isom', ['isom', 'mp41']))).toBe(false);
  });
  it('rejects PNG, JPEG and short input', () => {
    expect(isHeic(new Uint8Array([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0, 0, 0, 0, 0, 0, 0, 0]))).toBe(false);
    expect(isHeic(new Uint8Array([0xff, 0xd8, 0xff, 0xe0, 0, 0x10, 0x4a, 0x46, 0x49, 0x46, 0, 1, 1, 0, 0, 1]))).toBe(false);
    expect(isHeic(ftyp('heic').slice(0, 12))).toBe(false);
  });
});

describe('multipartBoundary', () => {
  it('parses plain and quoted boundaries', () => {
    expect(multipartBoundary('multipart/form-data; boundary=abc')).toBe('abc');
    expect(multipartBoundary('Multipart/Form-Data; charset=utf-8; boundary="a b:c"')).toBe('a b:c');
  });
  it('rejects other types and missing boundary', () => {
    expect(multipartBoundary('application/octet-stream')).toBeNull();
    expect(multipartBoundary('multipart/form-data')).toBeNull();
    expect(multipartBoundary(null)).toBeNull();
  });
});

describe('parseMultipart', () => {
  const enc = new TextEncoder();
  function concat(...parts: (string | Uint8Array)[]): Uint8Array {
    const bufs = parts.map((p) => (typeof p === 'string' ? enc.encode(p) : p));
    const out = new Uint8Array(bufs.reduce((n, b) => n + b.length, 0));
    let o = 0;
    for (const b of bufs) {
      out.set(b, o);
      o += b.length;
    }
    return out;
  }

  it('keeps binary content (including CRLF and dashes) and does not need filename', () => {
    const binary = new Uint8Array([0, 13, 10, 45, 45, 255, 13, 10, 13, 10, 1]);
    const body = concat(
      'preamble\r\n--XyZ\r\n',
      'Content-Disposition: form-data; name="full"\r\nContent-Type: image/heic\r\n\r\n',
      binary,
      '\r\n--XyZ\r\n',
      'content-disposition: form-data; name=thumb; filename="t.heic"\r\n\r\n',
      'abc',
      '\r\n--XyZ--\r\n',
    );
    const parts = parseMultipart(body, 'XyZ');
    expect([...parts.keys()]).toEqual(['full', 'thumb']);
    expect(parts.get('full')).toEqual(binary);
    expect(new TextDecoder().decode(parts.get('thumb'))).toBe('abc');
  });

  it('rejects a body without a closing delimiter', () => {
    const body = concat('--b\r\nContent-Disposition: form-data; name="full"\r\n\r\nabc');
    expect(() => parseMultipart(body, 'b')).toThrow(ApiError);
  });
});
