#!/usr/bin/env bash
# Apply the code as it was, then make the incident-time console change.
source "$(dirname "$0")/../../lib/tf.sh"
tf_apply "$1"
url=$(tf "$1" output -raw jobs_queue_url | sed 's#http://[^/]*#http://localhost:4566#')
aws_oob sqs set-queue-attributes --queue-url "$url" --attributes VisibilityTimeout=300
aws_oob sqs tag-queue --queue-url "$url" --tags oncall=INC-2291
