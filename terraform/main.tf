provider "aws" {
  region = var.aws_region
}

### IAM role for both Lambdas ###
resource "aws_iam_role" "lambda_exec" {
  name = "whatsapp-lambda-exec"
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

### Package & deploy message-checker ###
data "archive_file" "message_checker_zip" {
  type        = "zip"
  source_dir  = "${path.module}/../lambda/message-checker"
  output_path = "${path.module}/build/message-checker.zip"
}

resource "aws_lambda_function" "message_checker" {
  function_name = "message-checker-${var.deployment_id}"
  filename      = data.archive_file.message_checker_zip.output_path
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

### Package & deploy trigger-api ###
data "archive_file" "trigger_api_zip" {
  type        = "zip"
  source_dir  = "${path.module}/../lambda/trigger-api"
  output_path = "${path.module}/build/trigger-api.zip"
}

resource "aws_lambda_function" "trigger_api" {
  function_name = "trigger-api-${var.deployment_id}"
  filename      = data.archive_file.trigger_api_zip.output_path
  handler       = "handler.lambda_handler"
  runtime       = "python3.10"
  role          = aws_iam_role.lambda_exec.arn

  environment {
    variables = {
      REDIS_URL      = var.redis_url
      REDIS_PASSWORD = var.redis_password
      DYNAMO_TABLE   = var.dynamo_table_name
    }
  }
}

resource "aws_lambda_function_url" "trigger_api_url" {
  function_name      = aws_lambda_function.trigger_api.function_name
  authorization_type = "NONE"
}
