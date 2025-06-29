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
  default     = "default-id"
}

variable "deployment_id" {
  description = "Unique suffix for all resource names"
  type        = string
}

variable "public_subnet_ids" {
  description = "List of public subnet IDs"
  type        = list(string)
  default     = [
  "subnet-0e524ba4d7497f3ed",
  "subnet-02632a74d28164c3d",
  "subnet-00b1273c72f65d3ee",
  "subnet-0c05c7ec4456a1634",
  "subnet-0f560fea3c6c8523b",
  "subnet-07431bb62840ab0de"
]
}