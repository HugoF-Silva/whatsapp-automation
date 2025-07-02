variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "auth_api_key" {
  description = "Your EvolutionAPI key"
  type        = string
}

variable "evo_api_url" {
  description = "Your EvolutionAPI url"
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

variable "deployment_id" {
  description = "Workflow trigger identifier"
  type        = string
}

variable "lambda_code_bucket" {
  description = "S3 bucket for Lambda code"
  type        = string
}

variable "google_api_key" {
  description = "S3 bucket for Lambda code"
  type        = string
}

variable "lambda_secret_permission" {
  description = "S3 bucket for Lambda code"
  type        = string
}