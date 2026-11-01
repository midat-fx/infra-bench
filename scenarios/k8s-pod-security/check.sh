#!/usr/bin/env bash
source "$(dirname "$0")/../../lib/k8s.sh"
NS=k8s-pod-security
k8s_deploy $NS "$1"

[ "$(k get ns $NS -o jsonpath='{.metadata.labels.pod-security\.kubernetes\.io/enforce}')" = restricted ] ||
  fail "namespace must keep enforcing restricted"
v=$(k get ns $NS -o jsonpath='{.metadata.labels.pod-security\.kubernetes\.io/enforce-version}')
[ -z "$v" ] || [ "$v" = latest ] || fail "enforce-version pinned to $v"
k8s_wait_available $NS thumbnailer 40
ok "thumbnailer admitted under restricted"
