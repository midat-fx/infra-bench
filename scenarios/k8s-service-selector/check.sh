#!/usr/bin/env bash
source "$(dirname "$0")/../../lib/k8s.sh"
NS=k8s-service-selector
k8s_deploy $NS "$1"

for d in web admin; do k8s_wait_available $NS $d 40; done
sel=$(k get svc shop-public -n $NS -o json | jq -r '.spec.selector // {} | to_entries | map("\(.key)=\(.value)") | join(",")')
[ -n "$sel" ] || fail "shop-public has no selector"
want=$(k get pods -n $NS -l app=shop,component=web -o json | jq -c '[.items[].status.podIP] | sort')
admin=$(k get pods -n $NS -l component=admin -o json | jq -c '[.items[].status.podIP]')
for _ in 1 2 3 4 5; do
  got=$(k get endpointslices -n $NS -l kubernetes.io/service-name=shop-public -o json |
    jq -c '[.items[].endpoints[]? | select(.conditions.ready) | .addresses[0]] | sort')
  [ "$got" = "$want" ] && break
  sleep 2
done
jq -e --argjson g "$got" 'any(.[]; . as $ip | $g | index($ip))' <<<"$admin" >/dev/null &&
  fail "admin pod behind shop-public"
[ "$got" = "$want" ] || fail "endpoints $got, want web pods $want"
for _ in 1 2 3 4; do
  body=$(k exec -n $NS "$(k8s_pod $NS component=admin)" -- wget -q -T 3 -O - http://shop-public/ 2>&1) ||
    fail "GET http://shop-public/ failed"
  [ "$body" = web ] || fail "shop-public answered '$body'"
done
grep -q version <<<"$sel" && fail "selector pins a version label ($sel): breaks on the next rollout"
ok "shop-public -> web pods only"
