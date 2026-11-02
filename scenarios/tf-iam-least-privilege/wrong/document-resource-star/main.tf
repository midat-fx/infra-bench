resource "aws_s3_bucket" "exports" {
  bucket_prefix = "exports-"
}

resource "aws_sqs_queue" "export_done" {
  name_prefix = "export-done-"
}

data "aws_iam_policy_document" "assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "exporter" {
  name_prefix        = "exporter-"
  assume_role_policy = data.aws_iam_policy_document.assume.json
}

data "aws_iam_policy_document" "exporter" {
  statement {
    sid       = "ExportObjects"
    actions   = ["s3:GetObject", "s3:PutObject"]
    resources = ["*"]
  }
  statement {
    sid       = "NotifyDone"
    actions   = ["sqs:SendMessage"]
    resources = [aws_sqs_queue.export_done.arn]
  }
}

resource "aws_iam_policy" "exporter" {
  name_prefix = "exporter-"
  policy      = data.aws_iam_policy_document.exporter.json
}

resource "aws_iam_role_policy_attachment" "exporter" {
  role       = aws_iam_role.exporter.name
  policy_arn = aws_iam_policy.exporter.arn
}
