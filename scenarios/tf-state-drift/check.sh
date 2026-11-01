#!/usr/bin/env bash
# No reset here: the workspace's state and the live queue are the input.
source "$(dirname "$0")/../../lib/tf.sh"
ws=$1
! grep -rqs --include='*.tf' ignore_changes "$ws" || fail "lifecycle ignore_changes hides the drift instead of fixing it"
tf_init "$ws"
tf "$ws" state list | grep -qx aws_sqs_queue.jobs || fail "aws_sqs_queue.jobs is no longer in state"
url=$(tf "$ws" state show -no-color aws_sqs_queue.jobs | awk -F'"' '/^ *url *=/{print $2}' | sed 's#http://[^/]*#http://localhost:4566#')
live=$(aws_oob sqs get-queue-attributes --queue-url "$url" --attribute-names VisibilityTimeout --query Attributes.VisibilityTimeout --output text) ||
  fail "live queue not found"
[ "$live" = 300 ] || fail "live queue visibility timeout is $live, the incident fix (300) was reverted"
tags=$(aws_oob sqs list-queue-tags --queue-url "$url" --query Tags.oncall --output text)
[ "$tags" = INC-2291 ] || fail "live queue lost tag oncall=INC-2291"
rc=0
tf "$ws" plan -detailed-exitcode -no-color >"$ws/.plan.log" 2>&1 || rc=$?
[ $rc = 0 ] || { grep -E '^  [~+-]|# ' "$ws/.plan.log" | head -20; fail "terraform plan is not clean (exit $rc)"; }
ok "code matches the live queue, plan clean"
