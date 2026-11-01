resource "aws_sqs_queue" "jobs" {
  name_prefix                = "jobs-"
  visibility_timeout_seconds = 30
  message_retention_seconds  = 345600
  tags = {
    team = "billing"
  }
}

output "jobs_queue_url" {
  value = aws_sqs_queue.jobs.url
}
