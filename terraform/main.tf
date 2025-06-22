terraform {
  required_version = ">= 1.3.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 4.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

#
# ── QUEUES ──────────────────────────────────────────────────────────────────────
#
resource "aws_sqs_queue" "whatsapp_inbound" {
  name                        = "whatsapp-inbound-queue"
  visibility_timeout_seconds  = 30
  message_retention_seconds   = 1_209_600  # 14 days
}

resource "aws_sqs_queue" "reply_outbound" {
  name                        = "reply-outbound-queue"
  visibility_timeout_seconds  = 30
  message_retention_seconds   = 1_209_600
}

#
# ── ECS / FARGATE FOR EvolutionAPI ──────────────────────────────────────────────
#
data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

resource "aws_security_group" "allow_http" {
  name        = "allow-http"
  description = "Allow inbound HTTP"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_ecr_repository" "evolutionapi" {
  name = "evolutionapi"
}

resource "aws_ecs_cluster" "main" {
  name = "evolutionapi-cluster"
}

# Execution role for pulling images & pushing logs
data "aws_iam_policy_document" "ecs_task_exec_assume" {
  statement {
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
    actions = ["sts:AssumeRole"]
  }
}
resource "aws_iam_role" "ecs_task_execution_role" {
  name               = "ecsTaskExecutionRole"
  assume_role_policy = data.aws_iam_policy_document.ecs_task_exec_assume.json
}
resource "aws_iam_role_policy_attachment" "ecs_task_execution_attach" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# Task role for SQS access
data "aws_iam_policy_document" "ecs_task_assume" {
  statement {
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
    actions = ["sts:AssumeRole"]
  }
}
resource "aws_iam_role" "ecs_task_role" {
  name               = "evolutionapi-task-role"
  assume_role_policy = data.aws_iam_policy_document.ecs_task_assume.json
}
data "aws_iam_policy_document" "ecs_task_policy_doc" {
  statement {
    actions = [
      "sqs:SendMessage",
      "sqs:ReceiveMessage",
      "sqs:DeleteMessage",
      "sqs:GetQueueAttributes"
    ]
    resources = [
      aws_sqs_queue.whatsapp_inbound.arn,
      aws_sqs_queue.reply_outbound.arn
    ]
  }
}
resource "aws_iam_role_policy" "ecs_task_policy" {
  name   = "evolutionapi-ecs-policy"
  role   = aws_iam_role.ecs_task_role.id
  policy = data.aws_iam_policy_document.ecs_task_policy_doc.json
}

# ALB + TG + Listener
resource "aws_lb" "api" {
  name               = "evolutionapi-alb"
  load_balancer_type = "application"
  security_groups    = [aws_security_group.allow_http.id]
  subnets            = data.aws_subnets.default.ids
}

resource "aws_lb_target_group" "evolutionapi" {
  name     = "evolutionapi-tg"
  port     = 3000
  protocol = "HTTP"
  vpc_id   = data.aws_vpc.default.id

  health_check {
    path                = "/health"
    matcher             = "200-399"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 5
  }
}

resource "aws_lb_listener" "front_end" {
  load_balancer_arn = aws_lb.api.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.evolutionapi.arn
  }
}

# Task Definition & Service
resource "aws_ecs_task_definition" "evolutionapi" {
  family                   = "evolutionapi"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn
  task_role_arn            = aws_iam_role.ecs_task_role.arn

  container_definitions = jsonencode([
    {
      name      = "evolutionapi"
      image     = "${data.aws_caller_identity.current.account_id}.dkr.ecr.${var.aws_region}.amazonaws.com/${aws_ecr_repository.evolutionapi.name}:${var.evolutionapi_image_tag}"
      essential = true
      portMappings = [{
        containerPort = 3000
        protocol      = "tcp"
      }]
      environment = [
        { name = "WHATSAPP_INBOUND_QUEUE_URL", value = aws_sqs_queue.whatsapp_inbound.id },
        { name = "REPLY_OUTBOUND_QUEUE_URL",  value = aws_sqs_queue.reply_outbound.id },
      ]
    }
  ])
}

resource "aws_ecs_service" "evolutionapi" {
  name            = "evolutionapi-service"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.evolutionapi.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets         = data.aws_subnets.default.ids
    security_groups = [aws_security_group.allow_http.id]
    assign_public_ip = true
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.evolutionapi.arn
    container_name   = "evolutionapi"
    container_port   = 3000
  }

  depends_on = [aws_lb_listener.front_end]
}

#
# ── LAMBDA ORCHESTRATOR ────────────────────────────────────────────────────────
#
data "aws_iam_policy_document" "lambda_assume" {
  statement {
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
    actions = ["sts:AssumeRole"]
  }
}
resource "aws_iam_role" "lambda_role" {
  name               = "lambda-orchestrator-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

data "aws_iam_policy_document" "lambda_policy_doc" {
  statement {
    actions = [
      "sqs:ReceiveMessage",
      "sqs:DeleteMessage",
      "sqs:GetQueueAttributes",
      "sqs:SendMessage"
    ]
    resources = [
      aws_sqs_queue.whatsapp_inbound.arn,
      aws_sqs_queue.reply_outbound.arn
    ]
  }
  statement {
    actions = ["logs:CreateLogGroup","logs:CreateLogStream","logs:PutLogEvents"]
    resources = ["arn:aws:logs:*:*:*"]
  }
  statement {
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [var.gemini_secret_arn]
  }
}
resource "aws_iam_role_policy" "lambda_policy" {
  name   = "lambda-orchestrator-policy"
  role   = aws_iam_role.lambda_role.id
  policy = data.aws_iam_policy_document.lambda_policy_doc.json
}

resource "aws_lambda_function" "orchestrator" {
  function_name = "whatsapp-orchestrator"
  filename      = "${path.module}/../lambda-orchestrator/orchestrator.zip"
  handler       = "handler.handler"
  runtime       = "python3.11"
  role          = aws_iam_role.lambda_role.arn
  memory_size   = 512
  timeout       = 30

  environment {
    variables = {
      WHATSAPP_INBOUND_QUEUE_URL = aws_sqs_queue.whatsapp_inbound.id
      REPLY_OUTBOUND_QUEUE_URL   = aws_sqs_queue.reply_outbound.id
      GEMINI_SECRET_ARN          = var.gemini_secret_arn
    }
  }
}

resource "aws_lambda_event_source_mapping" "inbound_sqs" {
  event_source_arn  = aws_sqs_queue.whatsapp_inbound.arn
  function_name     = aws_lambda_function.orchestrator.arn
  batch_size        = 1
  enabled           = true
}
