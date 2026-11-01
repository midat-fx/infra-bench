#!/usr/bin/env bash
# Rego unit tests (`*_test.rego` next to each policy) on hand-written state
# fixtures. No cluster, no LocalStack: seconds, so `make test` runs it first.
source "$(dirname "${BASH_SOURCE[0]}")/env.sh"
rc=0
for d in "$ROOT"/scenarios/*/policy; do
  out=$(docker run --rm -v "$d:/policy" "$CONFTEST_IMAGE" verify --no-color -p /policy 2>&1) || rc=1
  echo "$(basename "$(dirname "$d")"): $(grep -E 'tests,' <<<"$out" || echo "$out")"
  grep -E '^FAIL' <<<"$out" || true
done
exit $rc
