resource "aws_s3_bucket" "invoices" {
  bucket_prefix = "invoices-"
}

resource "aws_s3_bucket_versioning" "invoices" {
  bucket = aws_s3_bucket.invoices.id
  versioning_configuration {
    status = "Enabled"
  }
}

output "bucket" {
  value = aws_s3_bucket.invoices.id
}
