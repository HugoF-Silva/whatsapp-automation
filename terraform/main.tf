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

resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy_attachment" "lambda_dynamo_redis" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonDynamoDBFullAccess"
}

resource "aws_lambda_function" "message_checker" {
  function_name = "message-checker-${var.deployment_id}"
  filename      = "${path.module}/build/message-checker.zip"
  handler       = "handler.lambda_handler"
  runtime       = "python3.10"
  role          = aws_iam_role.lambda_exec.arn

  environment {
    variables = {
      AUTHENTICATION_API_KEY       = var.auth_api_key
      EVO_API_URL                  = var.evo_api_url
      REDIS_URL                    = var.redis_url
      REDIS_PASSWORD               = var.redis_password
      TRIGGER_API_URL              = aws_lambda_function_url.trigger_api_url.function_url
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
  filename      = "${path.module}/build/trigger-api.zip"
  handler       = "handler.lambda_handler"
  runtime       = "python3.10"
  role          = aws_iam_role.lambda_exec.arn
  s3_bucket     = var.lambda_code_bucket
  s3_key        = var.lambda_trigger_api_key

  environment {
    variables = {
      UPSTASH_REDIS_REST_URL      = var.redis_url
      UPSTASH_REDIS_REST_TOKEN    = var.redis_password
      DYNAMO_TABLE                = var.dynamo_table_name
    }
  }
}

resource "aws_lambda_function_url" "trigger_api_url" {
  function_name      = aws_lambda_function.trigger_api.function_name
  authorization_type = "NONE"
}
