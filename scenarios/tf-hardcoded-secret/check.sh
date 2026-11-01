#!/usr/bin/env bash
source "$(dirname "$0")/../../lib/tf.sh"
HERE=$(cd "$(dirname "$0")" && pwd)
ws=$1
# The leaked value must be gone from every file we would commit.
hit=$(grep -rlF --exclude-dir=.terraform --exclude='terraform.tfstate*' --exclude='.*.log' \
  'Orders-2024-temp-pw' "$ws" || true)
[ -z "$hit" ] || fail "leaked password still present in: $(sed "s#^$ws/##" <<<"$hit" | tr '\n' ' ')"
tf_apply "$ws"
tf_policy "$ws" "$HERE/policy"
