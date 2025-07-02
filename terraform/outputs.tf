output "message_checker_url" {
  value = aws_lambda_function_url.message_checker_url.function_url
}

output "trigger_api_url" {
  value = aws_lambda_function_url.trigger_api_url.function_url
}

output "lambda_secret_permission_arn" {
  value = aws_iam_policy.secretsmanager_get.arn
}