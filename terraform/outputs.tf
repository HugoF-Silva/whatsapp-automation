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

# Function URL for EvolutionAPI webhook
output "message_checker_function_url" {
  description = "URL to configure in EvolutionAPI webhook settings"
  value = aws_lambda_function_url.message_checker.function_url
}

output "postgres_endpoint" {
  value = "postgresql://postgres:postgres123@${data.aws_db_instance.postgres.endpoint}:5432/postgres"
}

output "redis_endpoint" {
  value = "${data.aws_elasticache_cluster.redis.cache_nodes[0].address}:6379"
}