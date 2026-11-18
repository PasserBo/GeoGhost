/**
 * App version gate (docs/spec/changes/add-update-gate-and-switches/design.md).
 * Same rule as the SQL private.version_lt and the app's AppVersion: numeric
 * major.minor.patch, missing or non-numeric parts count as 0.
 */
export const VERSION_HEADER = 'x-geoghost-version';

export function versionParts(v: string): [number, number, number] {
  const p = v.trim().split('.');
  const n = (s: string | undefined) => {
    const m = /^\d{1,9}/.exec(s ?? '');
    return m ? Number(m[0]) : 0;
  };
  return [n(p[0]), n(p[1]), n(p[2])];
}

export function versionLessThan(a: string, b: string): boolean {
  const x = versionParts(a);
  const y = versionParts(b);
  for (let i = 0; i < 3; i++) {
    if (x[i]! !== y[i]!) return x[i]! < y[i]!;
  }
  return false;
}
