variable "aws_region" {
  description = "AWS region"
  type        = string
}

variable "lambda_code_bucket" {
  description = "S3 bucket for Lambda code"
  type        = string
}

variable "lambda_secret_permission" {
  description = "Name of the Lambda IAM policy"
  type        = string
}