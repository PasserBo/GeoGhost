#!/usr/bin/env bash
# End-to-end smoke test against the real backend (setup-online-backend T10/T11).
# Creates a throwaway guest, publishes one post, checks who can see it, retracts it and deletes
# the guest again, so it leaves nothing behind. Needs curl, jq and macOS `sips`.
#
#   server/scripts/smoke.sh                 # reads Config/Online.xcconfig
#   SUPABASE_URL=… ANON_KEY=… API_URL=… server/scripts/smoke.sh
set -euo pipefail

root="$(cd "$(dirname "$0")/../.." && pwd)"
xc="$root/Config/Online.xcconfig"
read_xc() { sed -n "s|^$1 *= *||p" "$xc" | sed 's|\$()||g'; }
SUPABASE_URL="${SUPABASE_URL:-$(read_xc GG_SUPABASE_URL)}"
ANON_KEY="${ANON_KEY:-$(read_xc GG_SUPABASE_ANON_KEY)}"
API_URL="${API_URL:-$(read_xc GG_ONLINE_API_URL)}"
[ -n "$SUPABASE_URL" ] && [ -n "$ANON_KEY" ] && [ -n "$API_URL" ] || { echo "backend not configured"; exit 1; }

work="$(mktemp -d)"
token=""
cleanup() {
  # Whatever happened, delete the throwaway guest and its images.
  if [ -n "$token" ]; then curl -s -o /dev/null -X DELETE -H "Authorization: Bearer $token" "$API_URL/v1/me" || true; fi
  rm -rf "$work"
}
trap cleanup EXIT

pass=0
ok()   { pass=$((pass + 1)); echo "  ok - $1"; }
fail() { echo "  FAIL - $1"; [ $# -gt 1 ] && echo "         $2"; exit 1; }
expect() { [ "$2" = "$3" ] && ok "$1" || fail "$1" "expected '$3', got '$2'"; }

# call METHOD PATH [JSON] — PostgREST/RPC as the guest; prints "status body"
db() {
  local method="$1" path="$2" body="${3:-}" auth="${4:-$token}"
  curl -s -w '\n%{http_code}' -X "$method" "$SUPABASE_URL/rest/v1/$path" \
    -H "apikey: $ANON_KEY" -H "Authorization: Bearer ${auth:-$ANON_KEY}" \
    -H "Content-Type: application/json" ${body:+-d "$body"}
}
status_of() { tail -n1 <<<"$1"; }
body_of()   { sed '$d' <<<"$1"; }

echo "backend: $SUPABASE_URL · $API_URL"

# 1. Anonymous sign-in
r=$(curl -s -w '\n%{http_code}' -X POST "$SUPABASE_URL/auth/v1/signup" -H "apikey: $ANON_KEY" \
      -H "Content-Type: application/json" -d '{}')
expect "anonymous sign-in" "$(status_of "$r")" 200
token=$(body_of "$r" | jq -r .access_token)
user=$(body_of "$r" | jq -r .user.id)
expect "user is anonymous" "$(body_of "$r" | jq -r .user.is_anonymous)" true

# 2. Publishing before agreeing to the rules is refused
cid=$(uuidgen | tr 'A-Z' 'a-z')
post_json=$(jq -nc --arg cid "$cid" --arg day "$(date -u +%F)" \
  '{client_artwork_id:$cid, kind:"sticker", lat:35.65949, lng:139.70055, locality:"Shibuya", country_code:"JP", captured_on:$day, width:400, height:400}')
r=$(db POST rpc/create_post "$post_json")
expect "publishing without a profile is refused" "$(body_of "$r" | jq -r .hint)" profile_required

# 3. Nickname + rules
r=$(db POST rpc/upsert_profile '{"nickname":"  smoke test  ","terms_version":1}')
expect "profile created" "$(status_of "$r")" 200
expect "nickname trimmed" "$(body_of "$r" | jq -r .nickname)" "smoke test"

# 4. Create the post (coordinates snapped by the server)
r=$(db POST rpc/create_post "$post_json")
expect "post created" "$(status_of "$r")" 200
post=$(body_of "$r" | jq -r .post_id)
expect "post starts as uploading" "$(body_of "$r" | jq -r .status)" uploading
r=$(db POST rpc/create_post "$post_json")
expect "retrying with the same artwork returns the same post" "$(body_of "$r" | jq -r .post_id)" "$post"
r=$(db GET "posts?id=eq.$post&select=lat,lng")
expect "latitude snapped to ~100 m" "$(body_of "$r" | jq -r '.[0].lat')" 35.659
expect "longitude snapped to ~100 m" "$(body_of "$r" | jq -r '.[0].lng')" 139.701

# 5. Upload the images through the Worker
sips -s format png -Z 1024 "$root/GeoGhost/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png" --out "$work/src.png" >/dev/null
sips -s format heic -Z 1024 "$work/src.png" --out "$work/full.heic" >/dev/null
sips -s format heic -Z 400 "$work/src.png" --out "$work/thumb.heic" >/dev/null
code=$(curl -s -o "$work/bad.json" -w '%{http_code}' -X PUT "$API_URL/v1/posts/$post/images" \
         -H "Authorization: Bearer $token" -F "full=@$work/src.png" -F "thumb=@$work/src.png")
expect "PNG is refused" "$code" 415
code=$(curl -s -o "$work/up.json" -w '%{http_code}' -X PUT "$API_URL/v1/posts/$post/images" \
         -H "Authorization: Bearer $token" -F "full=@$work/full.heic" -F "thumb=@$work/thumb.heic")
expect "upload accepted" "$code" 200
expect "new author's post waits for review" "$(jq -r .status "$work/up.json")" pending
code=$(curl -s -o /dev/null -w '%{http_code}' -X PUT "$API_URL/v1/posts/$post/images" \
         -H "Authorization: Bearer $ANON_KEY" -F "full=@$work/full.heic" -F "thumb=@$work/thumb.heic")
expect "upload without the guest's token is refused" "$code" 401

thumb_key=$(db GET "posts?id=eq.$post&select=thumb_key" | sed '$d' | jq -r '.[0].thumb_key')
code=$(curl -s -o "$work/thumb.out" -w '%{http_code}' "$API_URL/v1/images/$thumb_key")
expect "thumbnail can be read back" "$code" 200
cmp -s "$work/thumb.heic" "$work/thumb.out" && ok "thumbnail bytes unchanged" || fail "thumbnail bytes unchanged"

# 6. Who sees it
r=$(db GET "posts?id=eq.$post&select=status")
expect "author sees own pending post" "$(body_of "$r" | jq -r '.[0].status')" pending
r=$(db POST rpc/explore '{"min_lat":35.6,"min_lng":139.6,"max_lat":35.7,"max_lng":139.8}' "$ANON_KEY")
expect "explore works without an identity" "$(status_of "$r")" 200
expect "pending post is not on the world map" "$(body_of "$r" | jq --arg p "$post" '[.[] | select(.id == $p)] | length')" 0
r=$(db GET "posts?id=eq.$post&select=id" "" "$ANON_KEY")
expect "others cannot read the pending post" "$(body_of "$r" | jq length)" 0

# 7. Quota
r=$(db POST rpc/my_quota '{}')
expect "quota counts the post today" "$(body_of "$r" | jq -r .day_used)" 1
expect "monthly limit" "$(body_of "$r" | jq -r .month_limit)" 20

# 8. Retract
code=$(curl -s -o "$work/del.json" -w '%{http_code}' -X DELETE -H "Authorization: Bearer $token" "$API_URL/v1/posts/$post")
expect "retract" "$code" 200
expect "post removed" "$(jq -r .status "$work/del.json")" removed
code=$(curl -s -o /dev/null -w '%{http_code}' "$API_URL/v1/images/$thumb_key")
expect "image deleted with the post" "$code" 404
r=$(db POST rpc/my_quota '{}')
expect "retracting does not refund quota" "$(body_of "$r" | jq -r .day_used)" 1

# 9. Delete the guest's online data
code=$(curl -s -o "$work/me.json" -w '%{http_code}' -X DELETE -H "Authorization: Bearer $token" "$API_URL/v1/me")
expect "delete my online data" "$code" 200
r=$(db GET "profiles?id=eq.$user&select=id" "" "$ANON_KEY")
expect "profile gone" "$(body_of "$r" | jq length)" 0
token=""

echo "OK: $pass checks passed"
