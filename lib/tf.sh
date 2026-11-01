# shellcheck shell=bash
# Terraform + conftest helpers. Both run in containers on the kind network,
# where LocalStack answers as http://ib-localstack:4566. The AWS keys are
# LocalStack's documented dummy values, not credentials.
source "$(dirname "${BASH_SOURCE[0]}")/env.sh"

tf() {
  local ws=$1
  shift
  mkdir -p "$ROOT/.cache/tf-plugins"
  docker run --rm -i --network "$NET" -v "$ws:/ws" -w /ws \
    -v "$ROOT/.cache/tf-plugins:/plugins" \
    -e TF_PLUGIN_CACHE_DIR=/plugins -e TF_PLUGIN_CACHE_MAY_BREAK_DEPENDENCY_LOCK_FILE=true \
    -e TF_IN_AUTOMATION=1 -e TF_INPUT=0 \
    -e AWS_ACCESS_KEY_ID=test -e AWS_SECRET_ACCESS_KEY=test -e AWS_REGION=us-east-1 \
    "$TF_IMAGE" "$@"
}

tf_init() { tf "$1" init -no-color >/dev/null || { tf "$1" init -no-color | tail -20; fail "terraform init failed"; }; }

tf_apply() {
  tf_init "$1"
  tf "$1" apply -auto-approve -no-color >"$1/.apply.log" 2>&1 || {
    grep -E 'Error|error' -A4 "$1/.apply.log" | head -30
    fail "terraform apply failed"
  }
}

# Evaluate scenario Rego policies against the applied state. conftest prints
# each deny message as "FAIL - ... - <msg>"; we normalise to "FAIL: <msg>".
tf_policy() {
  local ws=$1 policy=$2 out
  # Piped, not via a file: virtiofs can serve a stale (empty) copy of a file
  # the host just wrote to a container in the VM.
  out=$(tf "$ws" show -json -no-color | docker run --rm -i -v "$policy:/policy" "$CONFTEST_IMAGE" \
    test --no-color --all-namespaces -p /policy - 2>&1) && { ok "policy"; return 0; }
  sed -nE 's/^FAIL - (- )?(main - )?/FAIL: /p' <<<"$out"
  grep -q '^FAIL - ' <<<"$out" || echo "$out"
  exit 1
}

# Run a command in LocalStack (awslocal is preinstalled there): the
# "someone changed it in the console" step of drift scenarios.
aws_oob() { docker exec "$LOCALSTACK" awslocal "$@"; }
