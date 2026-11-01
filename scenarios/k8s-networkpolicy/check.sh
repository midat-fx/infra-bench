#!/usr/bin/env bash
source "$(dirname "$0")/../../lib/k8s.sh"
NS=k8s-networkpolicy
k8s_deploy $NS "$1"

# Default deny must survive: some policy selects every pod, for Ingress, with no rules.
k get networkpolicy -n $NS -o json | jq -e '.items[] | select(.spec.podSelector == {}
  and (.spec.policyTypes | index("Ingress")) and ((.spec.ingress // []) | length == 0))' >/dev/null ||
  fail "default-deny ingress policy is gone"

for d in api frontend batch; do k8s_wait_available $NS $d 40; done
# Policies are programmed asynchronously; give the allow path a few tries.
for _ in 1 2 3 4 5; do k8s_can_reach $NS app=frontend http://api/ && break; sleep 2; done
k8s_can_reach $NS app=frontend http://api/ || fail "frontend cannot reach api"
! k8s_can_reach $NS app=batch http://api/ || fail "batch can reach api"
ok "frontend -> api allowed, batch -> api denied"
