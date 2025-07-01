variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "auth_api_key" {
  description = "Your EvolutionAPI key"
  type        = string
}

variable "whatsapp_version" {
  description = "Baileys session version"
  type        = string
}

variable "redis_url" {
  description = "Upstash Redis URL"
  type        = string
}

variable "redis_password" {
  description = "Upstash Redis password"
  type        = string
}

variable "dynamo_table_name" {
  description = "Name of your existing DynamoDB table"
  type        = string
}