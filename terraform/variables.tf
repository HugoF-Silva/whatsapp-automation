variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "evolutionapi_image" {
  description = "Docker image URI for EvolutionAPI"
  type        = string
}

variable "cache_cluster_id" {
  description = "ElastiCache cluster ID for external cache"
  type        = string
  default     = "whatsapp-cache"
}

variable "dynamodb_table_name" {
  description = "DynamoDB table for route times and estimates"
  type        = string
  default     = "RouteTimesTable"
}

variable "lambda_message_checker_s3_key" {
  description = "S3 key for message-checker Lambda zip"
  type        = string
}

variable "lambda_trigger_api_s3_key" {
  description = "S3 key for trigger-api Lambda zip"
  type        = string
}