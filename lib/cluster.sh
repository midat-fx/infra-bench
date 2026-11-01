#!/usr/bin/env bash
# up:   kind binary, one kind cluster, LocalStack, warm caches.
# down: delete both. Images stay cached unless PURGE=1.
source "$(dirname "${BASH_SOURCE[0]}")/env.sh"

install_kind() {
  local os arch url sum
  [ -x "$ROOT/.bin/kind" ] && "$ROOT/.bin/kind" version | grep -q "$KIND_VERSION" && return 0
  os=$(uname -s | tr '[:upper:]' '[:lower:]')
  arch=$(uname -m)
  case $arch in x86_64) arch=amd64 ;; aarch64) arch=arm64 ;; esac
  url="https://github.com/kubernetes-sigs/kind/releases/download/$KIND_VERSION/kind-$os-$arch"
  mkdir -p "$ROOT/.bin"
  curl -fsSL -o "$ROOT/.bin/kind.tmp" "$url"
  sum=$(curl -fsSL "$url.sha256sum" | awk '{print $1}')
  echo "$sum  $ROOT/.bin/kind.tmp" | shasum -a 256 -c - >/dev/null || fail "kind checksum mismatch"
  chmod +x "$ROOT/.bin/kind.tmp" && mv "$ROOT/.bin/kind.tmp" "$ROOT/.bin/kind"
}

up() {
  docker info >/dev/null 2>&1 || fail "docker is not reachable (DOCKER_HOST=${DOCKER_HOST:-default})"
  install_kind
  if ! kind get clusters 2>/dev/null | grep -qx "$CLUSTER"; then
    kind create cluster --name "$CLUSTER" --image "$NODE_IMAGE" \
      --kubeconfig "$ROOT/.cache/kubeconfig" --wait 180s
  fi
  if [ -z "$(docker ps -q -f "name=^$LOCALSTACK$")" ]; then
    docker rm -f "$LOCALSTACK" >/dev/null 2>&1 || true
    docker run -d --name "$LOCALSTACK" --network "$NET" \
      -e SERVICES=s3,iam,sts,sqs,ec2,secretsmanager "$LOCALSTACK_IMAGE" >/dev/null
  fi
  # Pull the one workload image once, so first-attempt timing is not network.
  docker exec "$NODE" crictl pull "$BUSYBOX" >/dev/null
  for _ in $(seq 60); do
    docker exec "$LOCALSTACK" curl -fs localhost:4566/_localstack/health >/dev/null 2>&1 && break
    sleep 2
  done
  docker exec "$LOCALSTACK" curl -fs localhost:4566/_localstack/health >/dev/null || fail "LocalStack not healthy"
  # Fill the provider cache once; parallel `terraform init`s then only link.
  source "$ROOT/lib/tf.sh"
  tf "$ROOT/lib/tf-warm" init -no-color >/dev/null
  echo "up: cluster $CLUSTER, $LOCALSTACK ready"
}

down() {
  kind delete cluster --name "$CLUSTER" --kubeconfig "$ROOT/.cache/kubeconfig" 2>/dev/null || true
  docker rm -f "$LOCALSTACK" >/dev/null 2>&1 || true
  if [ "${PURGE:-0}" = 1 ]; then
    docker rmi "$NODE_IMAGE" "$LOCALSTACK_IMAGE" "$TF_IMAGE" "$CONFTEST_IMAGE" >/dev/null 2>&1 || true
    rm -rf "$ROOT/.cache/tf-plugins"
  fi
  echo "down: cluster and LocalStack removed"
}

"$@"
