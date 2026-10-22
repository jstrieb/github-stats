#!/usr/bin/env bash
# Mint a read-only installation token for each allowed organization that has
# installed the stats GitHub App, and write them comma-separated to the file
# named by $1. Tokens are masked in the Actions log before they are written.
#
# Environment:
#   STATS_APP_CLIENT_ID    the App's client ID
#   STATS_APP_PRIVATE_KEY  the App's private key (PEM)
#   STATS_APP_ORGS         organizations to collect, separated by commas or
#                          whitespace. Required: the App must be public to be
#                          installed on organizations, so anyone can install
#                          it, and only listed installations are trusted.

set -euo pipefail

out="${1:?usage: $0 OUTPUT_FILE}"
: "${STATS_APP_CLIENT_ID:?}" "${STATS_APP_PRIVATE_KEY:?}"
allowed="$(tr -s ', \t\r' '[\n*]' <<<"${STATS_APP_ORGS:-}" | tr '[:upper:]' '[:lower:]' | sed '/^$/d')"
if [[ -z "$allowed" ]]; then
  echo "STATS_APP_ORGS is empty; not collecting organization repositories" >&2
  exit 1
fi

b64url() { openssl base64 -A | tr '+/' '-_' | tr -d '='; }

now="$(date +%s)"
header="$(printf '{"alg":"RS256","typ":"JWT"}' | b64url)"
payload="$(printf '{"iat":%d,"exp":%d,"iss":"%s"}' \
  "$((now - 60))" "$((now + 540))" "$STATS_APP_CLIENT_ID" | b64url)"
signature="$(printf '%s.%s' "$header" "$payload" \
  | openssl dgst -sha256 -binary -sign <(printf '%s\n' "$STATS_APP_PRIVATE_KEY") \
  | b64url)"
jwt="$header.$payload.$signature"

api() {
  curl -fsS \
    -H "Authorization: Bearer $jwt" \
    -H "Accept: application/vnd.github+json" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    "$@"
}

# Not a process substitution: its failure would not stop the script
installations="$(api "https://api.github.com/app/installations?per_page=100" \
  | jq -r '.[] | select(.account.type == "Organization") | "\(.id) \(.account.login)"')"

tokens=()
while read -r id login; do
  [[ -n "$id" ]] || continue
  if ! grep -qxF "${login,,}" <<<"$allowed"; then
    echo "Skipping an installation not in STATS_APP_ORGS" >&2
    continue
  fi
  token="$(api -X POST \
    -d '{"permissions":{"contents":"read","metadata":"read","administration":"read"}}' \
    "https://api.github.com/app/installations/$id/access_tokens" \
    | jq -r .token)"
  [[ "$token" == ghs_* ]] || { echo "Failed to mint an installation token" >&2; exit 1; }
  echo "::add-mask::$token"
  tokens+=("$token")
done <<<"$installations"

(IFS=,; printf '%s' "${tokens[*]}") >"$out"
echo "Minted ${#tokens[@]} organization token(s)" >&2
