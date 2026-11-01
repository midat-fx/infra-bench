#!/usr/bin/env bash
source "$(dirname "$0")/../../lib/k8s.sh"
NS=k8s-oom-crashloop
k8s_deploy $NS "$1"

c=$(k get deploy report-api -n $NS -o json | jq '.spec.template.spec.containers[0]')
[ "$(jq -r '.env[]? | select(.name == "CACHE_MB") | .value' <<<"$c")" = 48 ] || fail "CACHE_MB must stay 48"
[ "$(jq -c '.command' <<<"$c")" = '["sh","-c"]' ] || fail "container command changed"
grep -q 'bs=${CACHE_MB}M' <<<"$(jq -r '.args[0]' <<<"$c")" || fail "container args changed"
lim=$(jq -r '.resources.limits.memory // empty' <<<"$c")
[ -n "$lim" ] || fail "memory limit removed"
# Normalise Ki/Mi/Gi to MiB for the budget check.
mib=$(awk -v q="$lim" 'BEGIN{n=q+0; u=q; sub(/^[0-9.]+/,"",u);
  f=(u=="Ki")?1/1024:(u=="Mi")?1:(u=="Gi")?1024:(u=="")?1/1048576:(u=="M")?0.95:(u=="G")?953:-1; print n*f}')
awk -v m="$mib" 'BEGIN{exit !(m > 0 && m <= 256)}' || fail "memory limit $lim exceeds 256Mi"

k8s_wait_available $NS report-api 60
sleep 10
r=$(k8s_restarts $NS app=report-api)
# Between crashes both pods can look Ready for a moment, so the early OOM
# check in k8s_wait_available can miss it; name the reason here too.
why=$(k get pods -n $NS -l app=report-api -o json |
  jq -r '[.items[].status.containerStatuses[]?.lastState.terminated.reason // empty] | unique | join(",")')
[ "$r" = 0 ] || fail "pods restarted $r times after becoming ready (last termination: ${why:-unknown})"
ok "report-api stable with limit $lim"
