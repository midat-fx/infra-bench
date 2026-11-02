#!/usr/bin/env bash
# Pre-push and CI guard: nothing personal, secret or account-related in the
# tree, in any commit, or inside compressed files; one identity everywhere.
# Patterns are split ('a''b') so this file never matches itself.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

PATTERNS=(
  '/Us''ers/' '/ho''me/[a-z]'                        # machine paths
  'AKIA[0-9A-Z]{16}' 'gh[pousr]_[A-Za-z0-9]{30,}' 'github''_pat_' 'sk-''ant-'
  'xox[abpr]-[A-Za-z0-9]' 'BEGIN [A-Z ]*PRIVATE'' KEY'  # credentials
  '"type": ?"rate''_limit' 'overage''Status' 'out_of''_credits'  # CLI account events
  '[A-Za-z0-9._%+-]+@[A-Za-z0-9-]+\.[A-Za-z.]{2,}'    # e-mail addresses
)
# Addresses that are fine to publish.
ALLOW='users\.noreply\.github\.com|@example\.(com|org)|git@github\.com'

re=$(IFS='|'; echo "${PATTERNS[*]}")
bad=0
report() { echo "LEAK ($1):"; sed 's/^/  /' | cut -c1-200; bad=1; }

revs=$(git rev-list --all)
# shellcheck disable=SC2086 # one argument per revision
hits=$(git grep -nIE "$re" $revs -- . ':!lib/leak-check.sh' | grep -vE "$ALLOW" || true)
[ -z "$hits" ] || report "tree or history" <<<"$hits"

# git grep skips binaries; decompress every archive that ever existed.
while read -r obj path; do
  case $path in *.gz | *.tgz) ;; *) continue ;; esac
  hits=$(git cat-file -p "$obj" | gunzip -c 2>/dev/null | grep -nE "$re" | grep -vE "$ALLOW" || true)
  [ -z "$hits" ] || report "$path ($obj)" <<<"$hits"
done < <(git rev-list --all --objects | awk 'NF == 2')

# Author and committer of every commit: one identity, whatever it is, so no
# address is pinned here.
ids=$(git log --all --format='%an <%ae>%n%cn <%ce>' | sort | uniq -c)
[ "$(grep -c . <<<"$ids")" = 1 ] || report "more than one author/committer identity" <<<"$ids"
hits=$(git log --all --format='%h %B' | grep -iE 'co-authored-by|generated (with|by)' || true)
[ -z "$hits" ] || report "attribution trailers" <<<"$hits"

[ $bad = 0 ] && echo "leak-check: clean ($(wc -w <<<"$revs" | tr -d ' ') commits)"
exit $bad
