provider "aws" {
  region = var.aws_region
}

# 1. VPC & Networking
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  name    = "chatbot-vpc"
  azs     = var.azs
  public_subnets  = var.public_subnets
  private_subnets = var.private_subnets
}

# 2. ECR Repositories
resource "aws_ecr_repository" "evolution_api" { name = "evolution-api" }
resource "aws_ecr_repository" "n8n"           { name = "n8n" }
resource "aws_ecr_repository" "redis"         { name = "redis" }

# 3. ECS Cluster
resource "aws_ecs_cluster" "chatbot" { name = "chatbot-cluster" }

# 4. Application Load Balancer
resource "aws_lb" "alb" {
  name               = "chatbot-alb"
  internal           = false
  load_balancer_type = "application"
  subnets            = module.vpc.public_subnets
}

# 5. Target Groups & Listeners
#    Define aws_lb_target_group and aws_lb_listener for each service (paths /evolution, /n8n, /redis)

# 6. ECS Task Definitions & Services
#    evolution-api: desired_count = var.evolution_desired_count
#    n8n        : desired_count = 1 (autoscaling configured below)
#    redis      : desired_count = 1 (autoscaling configured below)

# 7. Application Auto Scaling Policies
#    aws_appautoscaling_target + aws_appautoscaling_policy for n8n and redis (CPU target 70%)

# 8. IAM Roles
#    ecsTaskExecutionRole for task execution