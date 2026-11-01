#!/usr/bin/env bash
source "$(dirname "$0")/../../lib/k8s.sh"
NS=k8s-rbac-least-privilege
k8s_deploy $NS "$1"

SA=system:serviceaccount:$NS:log-shipper
can() { [ "$(k auth can-i --as=$SA "$@" 2>/dev/null)" = yes ]; }

# Needed.
can list pods -n $NS || fail "cannot list pods"
can watch pods -n $NS || fail "cannot watch pods"
can get pods --subresource=log -n $NS || fail "cannot get pods/log"
# Not needed: a sample across the usual over-grants.
! can list pods -n kube-system || fail "can list pods in kube-system"
! can get secrets -n $NS || fail "can get secrets"
! can list configmaps -n $NS || fail "can list configmaps"
! can delete pods -n $NS || fail "can delete pods"
! can create pods --subresource=exec -n $NS || fail "can exec into pods"
! can list nodes || fail "can list nodes"
! can create rolebindings -n $NS || fail "can create rolebindings"
! can impersonate serviceaccounts -n $NS || fail "can impersonate"
ok "log-shipper limited to pods + pods/log in $NS"
