#!/usr/bin/env bash
# Compare the Cloudflare ranges in charts/values.yaml (websecure forwardedHeaders.trustedIPs)
# with api.cloudflare.com/client/v4/ips. On a difference: rewrite the list and open a PR.
# Jenkins builds the PR branch from the GitHub push webhook. The operator sets the release version.
# Usage: scripts/cloudflare-ips.sh   (run from the repository root; gh uses GH_TOKEN)
# Env: DRY_RUN=1               print the diff and the commands only; change nothing
#      CLOUDFLARE_TICKET_KEY   Jira key for the branch name (default DEVSECOPS-60)
# Test hooks (offline): IPS_FILE=<json file> replaces the API call; IPS_URL=<url> replaces the API URL.
set -euo pipefail

IPS_URL=${IPS_URL:-https://api.cloudflare.com/client/v4/ips}
VALUES=charts/values.yaml
LIST_PATH=.traefik.ports.websecure.forwardedHeaders.trustedIPs
KEY=${CLOUDFLARE_TICKET_KEY:-DEVSECOPS-60}
DRY_RUN=${DRY_RUN:-0}

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

if [[ -n ${IPS_FILE:-} ]]; then
  cp "$IPS_FILE" "$work/ips.json"
else
  curl -fsSL --max-time 30 --retry 2 -o "$work/ips.json" "$IPS_URL"
fi

# Fail closed: an empty or bad list would make Traefik distrust Cloudflare on every route.
if ! jq -e '
  .success == true
  and (.result.ipv4_cidrs | type == "array" and length > 0 and all(.[]; type == "string" and test("^[0-9]{1,3}(\\.[0-9]{1,3}){3}/[0-9]{1,2}$")))
  and (.result.ipv6_cidrs | type == "array" and length > 0 and all(.[]; type == "string" and test("^[0-9a-fA-F:]+/[0-9]{1,3}$")))
' "$work/ips.json" >/dev/null 2>&1; then
  echo '::error::The Cloudflare response has no valid ipv4_cidrs/ipv6_cidrs lists. Nothing changed.' >&2
  exit 1
fi

jq -c '.result.ipv4_cidrs + .result.ipv6_cidrs' "$work/ips.json" >"$work/new.json"
jq -r '.[]' "$work/new.json" | sort >"$work/new.txt"
yq "${LIST_PATH}[]" "$VALUES" | sort >"$work/old.txt"

if cmp -s "$work/old.txt" "$work/new.txt"; then
  echo "no change: $(wc -l <"$work/new.txt" | tr -d ' ') Cloudflare ranges are current."
  exit 0
fi

# Work on a copy in a dry run so the tree stays untouched.
if [[ "$DRY_RUN" == 1 ]]; then
  cp "$VALUES" "$work/values.yaml"
  TARGET_VALUES="$work/values.yaml"
else
  TARGET_VALUES="$VALUES"
fi

# Replace only the list lines under trustedIPs (yq -i would also drop the blank lines in the file).
# IPv4 first, then IPv6, in the order Cloudflare sends them.
jq -r '.[]' "$work/new.json" >"$work/new-order.txt"
awk -v list="$work/new-order.txt" '
  in_list && /^ *- / { if (!indent) { indent = $0; sub(/-.*/, "", indent) } next }
  in_list { while ((getline r < list) > 0) print indent "- " r; in_list = 0; done = 1 }
  { print }
  /^ *trustedIPs:$/ { in_list = 1; found++ }
  END { if (in_list) while ((getline r < list) > 0) print indent "- " r; if (found != 1) exit 2 }
' "$TARGET_VALUES" >"$work/values.new" || { echo '::error::trustedIPs must appear exactly once in charts/values.yaml.' >&2; exit 1; }
cat "$work/values.new" >"$TARGET_VALUES"
if ! diff -q <(yq "${LIST_PATH}[]" "$TARGET_VALUES") "$work/new-order.txt" >/dev/null; then
  echo '::error::The rewritten trustedIPs list does not match the Cloudflare list.' >&2
  exit 1
fi

BRANCH="bugfix/$KEY-cloudflare-ip-ranges-$(date +%Y%m%d)"
TITLE="$KEY: refresh Cloudflare IP ranges"
BODY="api.cloudflare.com/client/v4/ips differs from traefik.ports.websecure.forwardedHeaders.trustedIPs. The new list changes the Traefik arguments, so a sync restarts the Traefik pods one at a time."

if [[ "$DRY_RUN" == 1 ]]; then
  echo "dry run: the changes below are NOT written to the repository."
  diff -u "$VALUES" "$work/values.yaml" || true
  printf 'would run: %s\n' \
    "git checkout -b $BRANCH" \
    "git add $VALUES" \
    "git commit -m 'fix(chart): refresh Cloudflare IP ranges'" \
    "git push origin $BRANCH" \
    "gh pr create --base main --head $BRANCH --title '$TITLE' --body '$BODY'"
  exit 0
fi

git config user.name 'github-actions[bot]'
git config user.email '41898282+github-actions[bot]@users.noreply.github.com'
git checkout -b "$BRANCH"
git add "$VALUES"
git commit -m 'fix(chart): refresh Cloudflare IP ranges'
git push origin "$BRANCH"
gh pr create --base main --head "$BRANCH" --title "$TITLE" --body "$BODY"
