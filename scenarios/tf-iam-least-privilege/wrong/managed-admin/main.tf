resource "aws_s3_bucket" "exports" {
  bucket_prefix = "exports-"
}

resource "aws_sqs_queue" "export_done" {
  name_prefix = "export-done-"
}

resource "aws_iam_role" "exporter" {
  name_prefix = "exporter-"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_policy" "exporter" {
  name_prefix = "exporter-"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "ExportObjects"
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:PutObject"]
        Resource = "${aws_s3_bucket.exports.arn}/*"
      },
      {
        Sid      = "NotifyDone"
        Effect   = "Allow"
        Action   = "sqs:SendMessage"
        Resource = aws_sqs_queue.export_done.arn
      },
    ]
  })
}

resource "aws_iam_role_policy_attachment" "exporter" {
  role       = aws_iam_role.exporter.name
  policy_arn = aws_iam_policy.exporter.arn
}

resource "aws_iam_role_policy_attachment" "admin" {
  role       = aws_iam_role.exporter.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}
