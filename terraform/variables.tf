variable "aws_region" {
  type    = string
  default = "sa-east-1"
}

variable "evolutionapi_image_tag" {
  type        = string
  description = "Docker image tag (e.g. Git SHA) for EvolutionAPI"
}

variable "gemini_secret_arn" {
  type        = string
  description = "ARN of Secrets Manager Secret holding your Gemini API key"
}
