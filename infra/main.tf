# infra/main.tf
provider "aws" {
  region = "us-east-1"
}

######################
# 1) Queues
######################

resource "aws_sqs_queue" "whatsapp_inbound" {
  name                       = "whatsapp-inbound"
  visibility_timeout_seconds = 60
  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.whatsapp_inbound_dlq.arn
    maxReceiveCount     = 5
  })
}

resource "aws_sqs_queue" "whatsapp_inbound_dlq" {
  name = "whatsapp-inbound-dlq"
}

resource "aws_sqs_queue" "reply_outbound" {
  name                       = "reply-outbound"
  visibility_timeout_seconds = 60
  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.reply_outbound_dlq.arn
    maxReceiveCount     = 5
  })
}

resource "aws_sqs_queue" "reply_outbound_dlq" {
  name = "reply-outbound-dlq"
}

######################
# 2) Lambda Orchestrator
######################

data "archive_file" "lambda_zip" {
  type        = "zip"
  source_dir  = "${path.module}/lambda/src"
  output_path = "${path.module}/lambda/function.zip"
}

resource "aws_iam_role" "lambda_exec" {
  name = "whatsapp-orchestrator-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

data "aws_iam_policy_document" "lambda_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_lambda_function" "orchestrator" {
  function_name = "WhatsappOrchestrator"
  role          = aws_iam_role.lambda_exec.arn
  handler       = "handler.lambda_handler"
  runtime       = "python3.9"
  filename      = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  timeout       = 30
  environment {
    variables = {
      INBOUND_QUEUE_URL  = aws_sqs_queue.whatsapp_inbound.id
      OUTBOUND_QUEUE_URL = aws_sqs_queue.reply_outbound.id
      N8N_WEBHOOK_URL    = var.n8n_webhook_url
      BACKEND_API_URL    = var.backend_api_url
      GEMINI_API_KEY     = var.gemini_api_key
    }
  }
}

resource "aws_lambda_event_source_mapping" "inbound_to_lambda" {
  event_source_arn = aws_sqs_queue.whatsapp_inbound.arn
  function_name    = aws_lambda_function.orchestrator.arn
  batch_size       = 1
  enabled          = true
}

######################
# 3) ECR repos
######################

resource "aws_ecr_repository" "evolutionapi" {
  name = "evolutionapi"
}

resource "aws_ecr_repository" "n8n" {
  name = "n8n"
}

resource "aws_ecr_repository" "worker" {
  name = "evolutionapi-worker"
}

######################
# 4) ECS cluster + Fargate poller
######################

resource "aws_ecs_cluster" "worker_cluster" {
  name = "evoapi-poller-cluster"
}

resource "aws_iam_role" "ecs_task_exec" {
  name = "evoapi-poller-exec-role"
  assume_role_policy = data.aws_iam_policy_document.ecs_task_assume.json
}

data "aws_iam_policy_document" "ecs_task_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role_policy_attachment" "ecs_task_ecr" {
  role       = aws_iam_role.ecs_task_exec.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

resource "aws_iam_role_policy_attachment" "ecs_task_sqs" {
  role       = aws_iam_role.ecs_task_exec.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSQSFullAccess"
}

resource "aws_ecs_task_definition" "worker" {
  family                   = "evoapi-poller"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = aws_iam_role.ecs_task_exec.arn

  container_definitions = jsonencode([{
    name      = "worker"
    image     = "${aws_ecr_repository.worker.repository_url}:latest"
    essential = true
    environment = [
      { name = "OUTBOUND_QUEUE_URL", value = aws_sqs_queue.reply_outbound.id }
    ]
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = "/ecs/evoapi-poller"
        "awslogs-region"        = "us-east-1"
        "awslogs-stream-prefix" = "ecs"
      }
    }
  }])
}

resource "aws_ecs_service" "worker" {
  name            = "evoapi-poller-service"
  cluster         = aws_ecs_cluster.worker_cluster.id
  task_definition = aws_ecs_task_definition.worker.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets         = var.private_subnets
    security_groups = [var.worker_sg]
    assign_public_ip = false
  }
}
