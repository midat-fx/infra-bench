#!/usr/bin/env bash
source "$(dirname "$0")/../../lib/tf.sh"
HERE=$(cd "$(dirname "$0")" && pwd)
tf_apply "$1"
tf_policy "$1" "$HERE/policy"
