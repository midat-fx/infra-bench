# shellcheck shell=bash
# Kubernetes helpers. kubectl runs inside the kind node container, so the host
# needs neither kubectl nor a reachable API port (colima's port forwarding is
# unreliable, and this keeps the client version equal to the server version).
source "$(dirname "${BASH_SOURCE[0]}")/env.sh"

k() { docker exec -i -e KUBECONFIG=/etc/kubernetes/admin.conf "$NODE" kubectl "$@"; }

# Delete everything a previous attempt left: the namespace, plus cluster-scoped
# RBAC that is labelled for it or that grants anything to its service accounts.
k8s_reset() {
  local ns=$1 crb
  k delete clusterrole,clusterrolebinding -l "bench=$ns" --ignore-not-found >/dev/null
  for crb in $(k get clusterrolebindings -o json |
    jq -r --arg ns "$ns" '.items[] | select(any(.subjects[]?; .namespace == $ns)) | .metadata.name'); do
    k delete clusterrolebinding "$crb" >/dev/null
  done
  if k get ns "$ns" >/dev/null 2>&1; then
    k delete pods --all -n "$ns" --force --grace-period=0 >/dev/null 2>&1 || true
    k delete ns "$ns" --wait=true --timeout=300s >/dev/null || fail "infra: namespace $ns not deleted in 300s"
  fi
}

# Fresh namespace, then every manifest in the workspace, in file-name order.
k8s_deploy() {
  local ns=$1 ws=$2 f
  k8s_reset "$ns"
  k create ns "$ns" >/dev/null
  for f in "$ws"/*.yaml; do
    [ -f "$f" ] && { echo "---"; cat "$f"; }
  done | k apply -f - || fail "kubectl apply rejected the manifests"
}

# Wait until a Deployment is fully available. Bail out early on states that
# never heal by waiting (crash loops, OOM kills, admission/config errors).
k8s_wait_available() {
  local ns=$1 name=$2 timeout=${3:-60} end json sel want bad
  end=$((SECONDS + timeout))
  while [ "$SECONDS" -lt "$end" ]; do
    json=$(k get deploy "$name" -n "$ns" -o json 2>/dev/null) || fail "deployment $ns/$name not found"
    want=$(jq '.spec.replicas' <<<"$json")
    if [ "$(jq '.status.readyReplicas // 0' <<<"$json")" = "$want" ] &&
      [ "$(jq '.status.updatedReplicas // 0' <<<"$json")" = "$want" ]; then
      return 0
    fi
    bad=$(jq -r '.status.conditions[]? | select(.type == "ReplicaFailure" and .status == "True") | .message' <<<"$json")
    [ -z "$bad" ] || fail "deployment $ns/$name cannot create pods: $bad"
    sel=$(jq -r '.spec.selector.matchLabels | to_entries | map("\(.key)=\(.value)") | join(",")' <<<"$json")
    bad=$(k get pods -n "$ns" -l "$sel" -o json | jq -r '.items[].status.containerStatuses[]? |
      (.state.waiting.reason // empty), (.lastState.terminated.reason // empty)' |
      grep -m1 -E 'CrashLoopBackOff|OOMKilled|CreateContainerConfigError|ErrImagePull|ImagePullBackOff|Error' || true)
    [ -z "$bad" ] || fail "deployment $ns/$name pods are failing: $bad"
    sleep 2
  done
  fail "deployment $ns/$name not available after ${timeout}s"
}

# Total container restarts across pods matching a selector.
k8s_restarts() {
  k get pods -n "$1" -l "$2" -o json | jq '[.items[].status.containerStatuses[]?.restartCount] | add // 0'
}

# First pod name for a selector.
k8s_pod() {
  k get pods -n "$1" -l "$2" -o jsonpath='{.items[0].metadata.name}'
}

# Can pod (by selector) reach url? Exit status of a 3-second wget.
k8s_can_reach() {
  local ns=$1 sel=$2 url=$3
  k exec -n "$ns" "$(k8s_pod "$ns" "$sel")" -- wget -q -T 3 -O /dev/null "$url" >/dev/null 2>&1
}
