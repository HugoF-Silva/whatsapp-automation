provider "aws" {
  region = var.aws_region
}

# Get default VPC and subnets (simpler, less filtering)
data "aws_vpc" "default" {
  default = true
}

# Single Security Group for all components
resource "aws_security_group" "all_in_one" {
  name        = "all-in-one-sg-${var.deployment_id}"
  vpc_id      = data.aws_vpc.default.id
  description = "Allow all required traffic"
  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]   # Sandbox: open to all
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_db_subnet_group" "default" {
  name       = "default-db-subnet-${var.deployment_id}"
  subnet_ids = var.public_subnet_ids
}

resource "aws_db_instance" "evolution_postgres" {
  identifier              = "evolution-postgres-${var.deployment_id}"
  engine                  = "postgres"
  instance_class          = "db.t3.micro"
  allocated_storage       = 20
  username                = "postgres"
  password                = "postgres123"
  db_subnet_group_name    = aws_db_subnet_group.default.name
  vpc_security_group_ids  = [aws_security_group.all_in_one.id]
  skip_final_snapshot     = true
  publicly_accessible     = true
  port                    = 5432
}

# ECS Cluster and Task Definition
resource "aws_cloudwatch_log_group" "evolutionapi" {
  name              = "/ecs/evolutionapi"
  retention_in_days = 1
}

resource "aws_ecs_cluster" "evolutionapi" {
  name = "evolutionapi-cluster"
}

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
      environment = [
        { name = "REDIS_URL", value = aws_elasticache_cluster.external.cache_nodes[0].address },
        { name = "POSTGRES_URL", value = "postgresql://postgres:postgres123@${aws_db_instance.evolution_postgres.endpoint}:5432/postgres" }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = "/ecs/evolutionapi"
          awslogs-region        = "us-east-1"
          awslogs-stream-prefix = "ecs"
        }
      }
    }
  ])
}


resource "aws_iam_role" "ecs_task_execution" {
  name = "ecsTaskExecutionRole-${var.deployment_id}"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action    = "sts:AssumeRole"
        Effect    = "Allow"
        Principal = { Service = "ecs-tasks.amazonaws.com" }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution_policy" {
  role       = aws_iam_role.ecs_task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"   # Still simple
}

# ElastiCache Redis
resource "aws_elasticache_subnet_group" "default" {
  name       = "default-elasticache-subnet-${var.deployment_id}"
  subnet_ids = var.public_subnet_ids
}

resource "aws_elasticache_cluster" "external" {
  cluster_id           = "cache-${var.deployment_id}"
  engine               = "redis"
  node_type            = "cache.t3.micro"
  num_cache_nodes      = 1
  parameter_group_name = "default.redis7"
  port                 = 6379
  subnet_group_name    = aws_elasticache_subnet_group.default.name
  security_group_ids   = [aws_security_group.all_in_one.id]
}

# ALB for ECS
resource "aws_lb" "app" {
  name               = "evolutionapi-lb-${var.deployment_id}"
  internal           = false
  load_balancer_type = "application"
  subnets            = var.public_subnet_ids
  security_groups    = [aws_security_group.all_in_one.id]
}

resource "aws_lb_target_group" "evolutionapi" {
  name        = "tg-evolutionapi-${var.deployment_id}"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = data.aws_vpc.default.id
  target_type = "ip"
  health_check {
    path = "/health"
    matcher = "200"
  }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.app.arn
  port              = 80
  protocol          = "HTTP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.evolutionapi.arn
  }
}

# ECS Service with Scaling
resource "aws_ecs_service" "evolutionapi" {
  name            = "evolutionapi-service-${var.deployment_id}"
  cluster         = aws_ecs_cluster.evolutionapi.id
  task_definition = aws_ecs_task_definition.evolutionapi.arn
  desired_count   = 1
  launch_type     = "FARGATE"
  network_configuration {
    subnets         = var.public_subnet_ids
    security_groups = [aws_security_group.all_in_one.id]
    assign_public_ip = true
  }
  load_balancer {
    target_group_arn = aws_lb_target_group.evolutionapi.arn
    container_name   = "evolutionapi"
    container_port   = 80
  }
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

# Lambda Role
resource "aws_iam_role" "lambda_exec" {
  name = "lambdaExecutionRole-${var.deployment_id}"
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

# Lambdas (build .zip locally or in pipeline)
resource "aws_lambda_function" "message_checker" {
  function_name = "message-checker-${var.deployment_id}"
  filename      = "${path.module}/message_checker.zip"
  handler       = "handler.lambda_handler"
  runtime       = "python3.9"
  role          = aws_iam_role.lambda_exec.arn
  environment {
    variables = {
      REDIS_ENDPOINT = aws_elasticache_cluster.external.cache_nodes[0].address
    }
  }
  vpc_config {
    subnet_ids         = var.public_subnet_ids
    security_group_ids = [aws_security_group.all_in_one.id]
  }
}

resource "aws_lambda_function_url" "message_checker" {
  function_name      = aws_lambda_function.message_checker.function_name
  authorization_type = "NONE"
}

resource "aws_lambda_function" "trigger_api" {
  function_name = "trigger-api-${var.deployment_id}"
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
