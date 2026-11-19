/** Builds bytes starting with an ISO-BMFF ftyp box (rest zero-filled up to `size`). */
export function ftyp(major: string, compatible: string[] = ['mif1', 'heic'], size = 64): Uint8Array {
  const boxSize = 16 + compatible.length * 4;
  const out = new Uint8Array(Math.max(size, boxSize));
  new DataView(out.buffer).setUint32(0, boxSize);
  const text = 'ftyp' + major + '\0\0\0\0' + compatible.join('');
  for (let i = 0; i < text.length; i++) out[4 + i] = text.charCodeAt(i);
  return out;
}
