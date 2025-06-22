output "whatsapp_inbound_queue_url" {
  value = aws_sqs_queue.whatsapp_inbound.id
}

output "reply_outbound_queue_url" {
  value = aws_sqs_queue.reply_outbound.id
}

output "evolutionapi_url" {
  value = aws_lb.api.dns_name
}

output "orchestrator_lambda_arn" {
  value = aws_lambda_function.orchestrator.arn
}
