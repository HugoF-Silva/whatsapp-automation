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

data "aws_iam_policy" "secretsmanager_get" {
  name = var.lambda_secret_permission
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
  policy_arn = data.aws_iam_policy.secretsmanager_get.arn
}

locals {
  region      = var.aws_region      # e.g. "us-east-1"
  account_id  = data.aws_caller_identity.current.account_id
  calculator  = "MyEsriRouteCalculator"
  calc_arn    = "arn:aws:geo:${local.region}:${local.account_id}:route-calculator/${local.calculator}"
}

resource "aws_iam_role_policy" "lambda_location_calc" {
  name = "lambda-location-calc-policy"
  role = aws_iam_role.lambda_exec.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # allow the Lambda to check that the calculator exists
      {
        Effect   = "Allow"
        Action   = "geo:DescribeRouteCalculator"
        Resource = local.calc_arn
      },
      # allow the Lambda to actually calculate routes
      {
        Effect   = "Allow"
        Action   = "geo:CalculateRoute"
        Resource = local.calc_arn
      }
    ]
  })
}

resource "aws_lambda_function" "message_checker" {
  function_name = "message-checker-${var.deployment_id}"
  handler       = "handler.lambda_handler"
  runtime       = "python3.10"
  role          = aws_iam_role.lambda_exec.arn
  s3_bucket     = data.aws_s3_bucket.lambda_code.bucket
  s3_key        = "lambda/message-checker.zip"

  timeout=900
  memory_size=256

  environment {
    variables = {
      AUTHENTICATION_API_KEY       = var.auth_api_key
      EVO_API_URL                  = var.evo_api_url
      UPSTASH_REDIS_REST_URL       = var.redis_url
      UPSTASH_REDIS_REST_TOKEN               = var.redis_password
      TRIGGER_API_URL              = aws_lambda_function_url.trigger_api_url.function_url
      GOOGLE_API_KEY = var.google_api_key
      INSTANCE_NAME = var.instance_name
      OPEN_CAGE_KEY = var.open_cage_key
      FINDCEP_URL_HASH = var.findcep_url_hash
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
  timeout =900
  memory_size=256
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

# 1. CloudWatch log group for API access logs
resource "aws_cloudwatch_log_group" "api_access" {
  name              = "/aws/http-api/${aws_apigatewayv2_api.esim_webhook_api.id}"
  retention_in_days = 14
}

# 2. HTTP API
resource "aws_apigatewayv2_api" "esim_webhook_api" {
  name          = "EsimWebhookAPI"
  protocol_type = "HTTP"
}

# 3. Lambda-proxy integration
resource "aws_apigatewayv2_integration" "lambda_proxy" {
  api_id                 = aws_apigatewayv2_api.esim_webhook_api.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.message_checker.arn
  integration_method     = "POST"
  payload_format_version = "2.0"
}

# 4. Catch-all ANY /{proxy+} route
resource "aws_apigatewayv2_route" "proxy" {
  api_id    = aws_apigatewayv2_api.esim_webhook_api.id
  route_key = "ANY /{proxy+}"
  target    = "integrations/${aws_apigatewayv2_integration.lambda_proxy.id}"
}

# 5. Prod stage with throttling, metrics, and access logs
resource "aws_apigatewayv2_stage" "prod" {
  api_id      = aws_apigatewayv2_api.esim_webhook_api.id
  name        = "prod"
  auto_deploy = true

  default_route_settings {
    throttling_rate_limit    = 10
    throttling_burst_limit   = 60
    detailed_metrics_enabled = true
  }

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.api_access.arn
    format          = "$context.requestId $context.routeKey $context.status $context.error.message"
  }
}

# 6. Permission for API Gateway to invoke your Lambda
resource "aws_lambda_permission" "allow_apigw_invoke" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.message_checker.function_name
  principal     = "apigateway.amazonaws.com"
  # Use the execution ARN wildcard so that any stage/method can hit it:
  source_arn    = "${aws_apigatewayv2_api.esim_webhook_api.execution_arn}/*/*/*"
}
