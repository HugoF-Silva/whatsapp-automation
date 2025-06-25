output "alb_dns_name" {
  description = "DNS name of the ALB"
  value       = aws_lb.app.dns_name
}

output "message_checker_arn" {
  value = aws_lambda_function.message_checker.arn
}

output "trigger_api_arn" {
  value = aws_lambda_function.trigger_api.arn
}