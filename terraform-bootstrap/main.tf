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

  # optional hardening:
  acl    = "private"
  versioning {
    enabled = true
  }
  tags = {
    Name        = "lambda-code-bucket"
    Environment = "prod"
  }
}


resource "aws_iam_policy" "secretsmanager_get" {
  name = var.lambda_secret_permission
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = [
          "secretsmanager:GetSecretValue"
        ]
        Resource = "arn:aws:secretsmanager:${var.aws_region}:${data.aws_caller_identity.current.account_id}:secret:pseodonym/salt*"
      }
    ]
  })
}

resource "aws_location_route_calculator" "esri" {
  calculator_name = "MyEsriRouteCalculator"  # must be unique per AWS account :contentReference[oaicite:0]{index=0}
  data_source     = "Esri"                   # use Esri road-network + traffic data :contentReference[oaicite:1]{index=1}

  tags = {
    Name        = "MyEsriRouteCalculator"
  }
}