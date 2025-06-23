output "alb_dns_name" {
  description = "Application Load Balancer DNS name"
  value       = aws_lb.alb.dns_name
}

output "evolution_api_url" {
  description = "URL for the EvolutionAPI service"
  value       = "https://${aws_lb.alb.dns_name}/evolution"
}

output "n8n_url" {
  description = "URL for the n8n workflow UI"
  value       = "https://${aws_lb.alb.dns_name}/n8n"
}

output "redis_service_name" {
  description = "ECS service name for Redis"
  value       = aws_ecs_service.redis.name
}