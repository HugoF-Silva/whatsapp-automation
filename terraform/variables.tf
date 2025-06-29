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