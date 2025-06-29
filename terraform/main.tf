provider "aws" {
  region = var.aws_region
}

# ECS Cluster for EvolutionAPI
resource "aws_ecs_cluster" "evolutionapi" {
  name = "evolutionapi-cluster"
}

# Task Definition
resource "aws_ecs_task_definition" "evolutionapi" {
  family                   = "evolutionapi"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "512"
  memory                   = "1024"
  execution_role_arn       = aws_iam_role.ecs_task_execution.arn
  container_definitions    = jsonencode([
    {
      name      = "evolutionapi"
      image     = var.evolutionapi_image
      portMappings = [{ containerPort = 80, hostPort = 80 }]
      environment = [{ name = "REDIS_URL", value = aws_elasticache_cluster.external.cache_nodes[0].address }]
    }
  ])
}

# IAM Role for ECS Task Execution
resource "aws_iam_role" "ecs_task_execution" {
  name = "ecsTaskExecutionRolelat31"
  assume_role_policy = data.aws_iam_policy_document.ecs_task_execution.json
}

data "aws_iam_policy_document" "ecs_task_execution" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution_policy" {
  role       = aws_iam_role.ecs_task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

data "aws_vpc" "main" {
  filter {
    name   = "tag:Name"
    values = ["vpc-name"]
  }
}

data "aws_subnets" "private" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.main.id]
  }
}

# ALB for ECS Service and Lambda targets
resource "aws_lb" "app" {
  name               = "chatbot-lblat31"
  internal           = false
  load_balancer_type = "application"
  subnets            = data.aws_subnets.private.ids
}

resource "aws_lb_target_group" "evolutionapi" {
  name     = "tg-evolutionapilat31"
  port     = 80
  protocol = "HTTP"
  vpc_id   = data.aws_vpc.main.id
  target_type = "ip"
  health_check {
    path                = "/health"
    matcher             = "200"
    interval            = 30
    healthy_threshold   = 2
    unhealthy_threshold = 5
  }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.app.arn
  port              = "80"
  protocol          = "HTTP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.evolutionapi.arn
  }
}

# ECS Service with Auto Scaling
resource "aws_ecs_service" "evolutionapi" {
  name            = "evolutionapi-servicelat31"
  cluster         = aws_ecs_cluster.evolutionapi.id
  task_definition = aws_ecs_task_definition.evolutionapi.arn
  desired_count   = 1
  launch_type     = "FARGATE"
  network_configuration {
    subnets         = data.aws_subnets.private.ids
    security_groups = [aws_security_group.ecs_tasks.id]
  }
  load_balancer {
    target_group_arn = aws_lb_target_group.evolutionapi.arn
    container_name   = "evolutionapi"
    container_port   = 80
  }
  depends_on = [aws_lb_listener.http, aws_security_group.ecs_tasks, data.aws_subnets.private]
}

resource "aws_appautoscaling_target" "ecs" {
  max_capacity       = 5
  min_capacity       = 1
  resource_id        = "service/${aws_ecs_cluster.evolutionapi.name}/${aws_ecs_service.evolutionapi.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
}

resource "aws_appautoscaling_policy" "cpu_target" {
  name               = "ecs-cpu-autoscale"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.ecs.resource_id
  scalable_dimension = aws_appautoscaling_target.ecs.scalable_dimension
  service_namespace  = aws_appautoscaling_target.ecs.service_namespace

  target_tracking_scaling_policy_configuration {
    target_value       = 50.0
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }
    scale_in_cooldown  = 300
    scale_out_cooldown = 300
  }
}

data "archive_file" "trigger_api" {
  type        = "zip"
  source_dir  = "${path.module}/../lambda/trigger-api"      # Note: dash not underscore!
  output_path = "${path.module}/trigger_api.zip"
}

resource "aws_security_group" "redis_sglat31" {
  name        = "redis_sglat31"
  description = "Security group for Redis cluster"
  vpc_id      = data.aws_vpc.main.id

  # Example: open Redis port 6379 to your application servers (or restrict further!)
  ingress {
    from_port   = 6379
    to_port     = 6379
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"] # Change this to your application subnet or specific IPs!
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "redis-sg"
  }
}

resource "aws_security_group" "ecs_tasks" {
  name        = "ecs-tasks-sglat31"
  vpc_id      = data.aws_vpc.main.id
  description = "Allow ECS tasks to communicate with VPC endpoints"
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "vpce" {
  name   = "vpce-sglat31"
  vpc_id = data.aws_vpc.main.id

  ingress {
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = [aws_security_group.ecs_tasks.id]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  depends_on = [aws_security_group.ecs_tasks]
}

resource "aws_vpc_endpoint" "ecr_api" {
  vpc_id            = data.aws_vpc.main.id
  service_name      = "com.amazonaws.${var.aws_region}.ecr.api"
  vpc_endpoint_type = "Interface"
  subnet_ids        = data.aws_subnets.private.ids
  security_group_ids = [aws_security_group.vpce.id]
}

resource "aws_vpc_endpoint" "ecr_dkr" {
  vpc_id            = data.aws_vpc.main.id
  service_name      = "com.amazonaws.${var.aws_region}.ecr.dkr"
  vpc_endpoint_type = "Interface"
  subnet_ids        = data.aws_subnets.private.ids
  security_group_ids = [aws_security_group.vpce.id]
}

data "aws_route_tables" "private" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.main.id]
  }
}

resource "aws_vpc_endpoint" "s3" {
  vpc_id            = data.aws_vpc.main.id
  service_name      = "com.amazonaws.${var.aws_region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = data.aws_route_tables.private.ids
}

# ElastiCache Redis for external caching
resource "aws_elasticache_cluster" "external" {
  cluster_id           = var.cache_cluster_id
  engine               = "redis"
  node_type            = "cache.t3.micro"
  num_cache_nodes      = 1
  parameter_group_name = "default.redis7"
  port                 = 6379
  subnet_group_name    = aws_elasticache_subnet_group.redis_subnets.name
  security_group_ids   = [aws_security_group.redis_sglat31.id]
}

resource "aws_elasticache_subnet_group" "redis_subnets" {
  name       = "redis-subnet-grouplat31"
  subnet_ids = data.aws_subnets.private.ids
}

data "archive_file" "message_checker" {
  type        = "zip"
  source_dir  = "${path.module}/../lambda/message-checker"  # Note: dash not underscore!
  output_path = "${path.module}/message_checker.zip"
}

# Lambda: message-checker
resource "aws_lambda_function" "message_checker" {
  function_name = "message-checker"
  filename      = "${path.module}/message_checker.zip"
  handler       = "handler.lambda_handler"
  runtime       = "python3.9"
  role          = aws_iam_role.lambda_exec.arn
  environment {
    variables = {
      REDIS_ENDPOINT = aws_elasticache_cluster.external.cache_nodes[0].address
    }
  }
}

resource "aws_lambda_function_url" "message_checker" {
  function_name      = aws_lambda_function.message_checker.function_name
  authorization_type = "NONE"
}

# Lambda: trigger-apilat31
resource "aws_lambda_function" "trigger_api" {
  function_name = "trigger-apilat31"
  filename      = "${path.module}/trigger_api.zip"
  handler       = "handler.lambda_handler"
  runtime       = "python3.9"
  role          = aws_iam_role.lambda_exec.arn
  environment {
    variables = {
      DYNAMODB_TABLE = "test"
    }
  }
}

# IAM Role and Policy for Lambdas
resource "aws_iam_role" "lambda_exec" {
  name = "lambdaExecutionRolelat31"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action    = "sts:AssumeRole"
        Principal = { Service = "lambda.amazonaws.com" }
        Effect    = "Allow"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_policy" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy_attachment" "lambda_dynamodb" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonDynamoDBFullAccess"
}

resource "aws_iam_role_policy_attachment" "lambda_elasticache" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonElastiCacheFullAccess"
}
