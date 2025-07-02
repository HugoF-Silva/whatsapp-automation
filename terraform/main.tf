terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.44"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

data "aws_s3_bucket" "lambda_code" {
  bucket = var.lambda_code_bucket
}

### IAM role for both Lambdas ###
resource "aws_iam_role" "lambda_exec" {
  name = "whatsapp-lambda-exec-${var.deployment_id}"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

data "aws_iam_policy_document" "lambda_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      identifiers = ["lambda.amazonaws.com"]
      type        = "Service"
    }
  }
}

data "aws_caller_identity" "current" {}

resource "aws_iam_policy" "secretsmanager_get" {
  name = "allow-get-secret-pseodonym-salt"
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

resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy_attachment" "lambda_dynamo_redis" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonDynamoDBFullAccess"
}

resource "aws_iam_role_policy_attachment" "lambda_secrets" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = aws_iam_policy.secretsmanager_get.arn
}

resource "aws_lambda_function" "message_checker" {
  function_name = "message-checker-${var.deployment_id}"
  handler       = "handler.lambda_handler"
  runtime       = "python3.10"
  role          = aws_iam_role.lambda_exec.arn
  s3_bucket     = data.aws_s3_bucket.lambda_code.bucket
  s3_key        = "lambda/message-checker.zip"

  environment {
    variables = {
      AUTHENTICATION_API_KEY       = var.auth_api_key
      EVO_API_URL                  = var.evo_api_url
      UPSTASH_REDIS_REST_URL       = var.redis_url
      UPSTASH_REDIS_REST_TOKEN               = var.redis_password
      TRIGGER_API_URL              = aws_lambda_function_url.trigger_api_url.function_url
      GOOGLE_API_KEY = var.google_api_key
    }
  }
}

### Expose as HTTPS endpoint without API Gateway ###
resource "aws_lambda_function_url" "message_checker_url" {
  function_name      = aws_lambda_function.message_checker.function_name
  authorization_type = "NONE"
}

resource "aws_lambda_function" "trigger_api" {
  function_name = "trigger-api-${var.deployment_id}"
  handler       = "handler.lambda_handler"
  runtime       = "python3.10"
  role          = aws_iam_role.lambda_exec.arn
  s3_bucket     = data.aws_s3_bucket.lambda_code.bucket
  s3_key        = "lambda/trigger-api.zip"

  environment {
    variables = {
      DYNAMO_TABLE                = var.dynamo_table_name
    }
  }
}

resource "aws_lambda_function_url" "trigger_api_url" {
  function_name      = aws_lambda_function.trigger_api.function_name
  authorization_type = "NONE"
}