terraform {
  required_version = ">= 1.6"
  required_providers {
    aws    = { source = "hashicorp/aws", version = "5.100.0" }
    random = { source = "hashicorp/random", version = "3.7.2" }
  }
}

# LocalStack. Credentials come from AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY.
provider "aws" {
  region                      = "us-east-1"
  s3_use_path_style           = true
  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_requesting_account_id  = true

  endpoints {
    ec2            = "http://ib-localstack:4566"
    iam            = "http://ib-localstack:4566"
    s3             = "http://ib-localstack:4566"
    secretsmanager = "http://ib-localstack:4566"
    sqs            = "http://ib-localstack:4566"
    sts            = "http://ib-localstack:4566"
  }
}
