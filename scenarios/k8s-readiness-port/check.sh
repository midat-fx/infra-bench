#!/usr/bin/env bash
source "$(dirname "$0")/../../lib/k8s.sh"
NS=k8s-readiness-port
k8s_deploy $NS "$1"

p=$(k get deploy storefront -n $NS -o json | jq '.spec.template.spec.containers[0].readinessProbe')
[ "$p" != null ] || fail "readinessProbe missing"
[ "$(jq -r '.httpGet.path // empty' <<<"$p")" = /healthz ] || fail "readinessProbe must be httpGet on /healthz"

k8s_wait_available $NS storefront 40
n=$(k get endpointslices -n $NS -l kubernetes.io/service-name=storefront -o json |
  jq '[.items[].endpoints[]? | select(.conditions.ready)] | length')
[ "$n" -ge 2 ] || fail "service has $n ready endpoints, want 2"
body=$(k exec -n $NS "$(k8s_pod $NS app=storefront)" -- wget -q -T 3 -O - http://storefront/ 2>&1) || fail "GET http://storefront/ failed: $body"
[ "$body" = storefront ] || fail "unexpected body: $body"
ok "storefront ready behind its service"
