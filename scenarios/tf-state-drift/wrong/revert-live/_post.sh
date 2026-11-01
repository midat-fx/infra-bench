#!/usr/bin/env bash
# "Fix" the drift the other way: re-apply the old code.
source "$IB_ROOT/lib/tf.sh"
tf "$PWD" apply -auto-approve -no-color
