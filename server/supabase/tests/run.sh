#!/usr/bin/env bash
# Runs the migration + SQL tests in a throwaway postgres:16 container.
# LOCAL TESTS ONLY: 00_supabase_stub.sql fakes the parts of Supabase we rely on.
#
#   server/supabase/tests/run.sh            # all tests
#   PG_IMAGE=postgres:15 server/supabase/tests/run.sh
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/.." && pwd)"
image="${PG_IMAGE:-postgres:16}"
name="geoghost-sqltest-$$"

docker run -d --rm --name "$name" -e POSTGRES_PASSWORD=postgres \
  -v "$root:/work:ro" "$image" >/dev/null
trap 'docker rm -f "$name" >/dev/null 2>&1 || true' EXIT

# TCP readiness: the entrypoint's temporary init server only listens on a socket.
for _ in $(seq 1 60); do
  docker exec "$name" pg_isready -q -h 127.0.0.1 -U postgres && break
  sleep 1
done

run() { # file
  docker exec "$name" psql -h 127.0.0.1 -U postgres -d postgres -X -q \
    -v ON_ERROR_STOP=1 -o /dev/null -f "$1"
}

run /work/tests/00_supabase_stub.sql
for m in "$root"/migrations/*.sql; do
  echo "== migration $(basename "$m")"
  run "/work/migrations/$(basename "$m")"
done
run /work/tests/01_fixtures.sql

total=0
failed=0
for t in "$here"/[1-9][0-9]_*.sql; do
  f="$(basename "$t")"
  if out="$(run "/work/tests/$f" 2>&1)"; then status=ok; else status=FAILED; failed=$((failed + 1)); fi
  n="$(grep -c 'NOTICE:  ok - ' <<<"$out" || true)"
  total=$((total + n))
  echo "== $f: $n passed ($status)"
  grep -E 'NOTICE:  ok - |ERROR|not ok' <<<"$out" | sed -E 's/^psql:[^ ]+ (NOTICE|ERROR):  /  \1 /; s/^  NOTICE /  /' || true
done

echo
echo "TOTAL: $total assertions passed, $failed file(s) failed"
[ "$failed" -eq 0 ]
