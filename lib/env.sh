# shellcheck shell=bash
# Pinned versions and names shared by every script. Source, don't execute.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export PATH="$ROOT/.bin:$PATH"

# colima puts the socket under ~/.colima; Docker Desktop / Linux use the default.
if [ -z "${DOCKER_HOST:-}" ] && [ -S "$HOME/.colima/default/docker.sock" ]; then
  export DOCKER_HOST="unix://$HOME/.colima/default/docker.sock"
fi
# Private docker config: the user's one may point at a credential helper that
# is not installed (docker-credential-desktop). All images here are public.
export DOCKER_CONFIG="$ROOT/.cache/docker"
mkdir -p "$DOCKER_CONFIG"
[ -f "$DOCKER_CONFIG/config.json" ] || echo '{"auths":{}}' >"$DOCKER_CONFIG/config.json"

KIND_VERSION=v0.33.0
NODE_IMAGE=kindest/node:v1.37.0@sha256:a1ed56cfb0e7b93589bdf97c8cd566405a265939e3620fc4f5de89adff580ae5
# 4.14 is the last community image that starts without an auth token.
LOCALSTACK_IMAGE=localstack/localstack:4.14.0
TF_IMAGE=hashicorp/terraform:1.17.1
CONFTEST_IMAGE=openpolicyagent/conftest:v0.71.1
BUSYBOX=busybox:1.37.0

CLUSTER=infra-bench
NODE=$CLUSTER-control-plane
NET=kind
LOCALSTACK=ib-localstack

fail() { echo "FAIL: $*"; exit 1; }
ok() { echo "ok: $*"; }
