resource "aws_s3_bucket" "invoices" {
  bucket_prefix = "invoices-"
}

resource "aws_s3_bucket_versioning" "invoices" {
  bucket = aws_s3_bucket.invoices.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "invoices" {
  bucket = aws_s3_bucket.invoices.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_ownership_controls" "invoices" {
  bucket = aws_s3_bucket.invoices.id
  rule {
    object_ownership = "BucketOwnerPreferred"
  }
}

resource "aws_s3_bucket_acl" "invoices" {
  depends_on = [aws_s3_bucket_ownership_controls.invoices]
  bucket     = aws_s3_bucket.invoices.id
  acl        = "private"
}

output "bucket" {
  value = aws_s3_bucket.invoices.id
}
