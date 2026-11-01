#!/usr/bin/env bash
source "$IB_ROOT/lib/tf.sh"
tf "$PWD" state rm aws_sqs_queue.jobs
