terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~>5.44"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

resource "aws_s3_bucket" "lambda_code" {
  bucket = var.lambda_code_bucket
  acl    = "private"
  versioning { enabled = true }
}