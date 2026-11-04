#!/usr/bin/env bash
source "$(dirname "$0")/../../lib/k8s.sh"
NS=k8s-startup-probe
t0=$SECONDS
k8s_deploy $NS "$1"

c=$(k get deploy ledger -n $NS -o json | jq '.spec.template.spec.containers[0]')
jq -e '.args | join("\n") | contains("sleep 20")' <<<"$c" >/dev/null || fail "app start-up changed: the 20 s load must stay"
p=$(jq '.livenessProbe' <<<"$c")
[ "$p" != null ] || fail "livenessProbe missing"
[ "$(jq -r '.httpGet.path // empty' <<<"$p")" = /healthz ] || fail "livenessProbe must be httpGet on /healthz"
# Probe defaults: period 10 s, failureThreshold 3, initialDelay 0.
n=$(jq '(.initialDelaySeconds // 0) + (.periodSeconds // 10) * (.failureThreshold // 3)' <<<"$p")
[ "$n" -le 10 ] || fail "liveness takes ${n}s to restart a hung server, want at most 10s"

k8s_wait_available $NS ledger 90
# Watch past the slow start: a probe that kills it shows up as restarts.
left=$((t0 + 40 - SECONDS))
[ "$left" -le 0 ] || sleep "$left"
k8s_wait_available $NS ledger 10
r=$(k8s_restarts $NS app=ledger)
[ "$r" = 0 ] || fail "ledger restarted $r times"
ok "ledger up after its slow start, no restarts"
