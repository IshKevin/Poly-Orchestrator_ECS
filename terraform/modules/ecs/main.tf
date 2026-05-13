locals {
  name_prefix = "${var.project_name}-${var.environment}"
  sd_namespace = "${var.project_name}.local"

  services = {
    frontend = {
      image          = var.frontend_image
      cpu            = var.frontend_cpu
      memory         = var.frontend_memory
      desired_count  = var.frontend_desired_count
      container_port = 3000
      security_group = var.frontend_security_group_id
      target_group   = var.frontend_target_group_arn
      health_cmd     = "node -e \"require('http').get('http://localhost:3000/health', r => process.exit(r.statusCode===200?0:1))\""
      start_period   = 15
    }
    backend = {
      image          = var.backend_image
      cpu            = var.backend_cpu
      memory         = var.backend_memory
      desired_count  = var.backend_desired_count
      container_port = 5000
      security_group = var.backend_security_group_id
      target_group   = var.backend_target_group_arn
      health_cmd     = "python -c \"import urllib.request; urllib.request.urlopen('http://localhost:5000/api/health')\""
      start_period   = 30
    }
  }
}

# ── ECS Cluster ───────────────────────────────────────────────────────────────

resource "aws_ecs_cluster" "this" {
  name = "${local.name_prefix}-cluster"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }

  tags = merge(var.tags, { Name = "${local.name_prefix}-cluster" })
}

resource "aws_ecs_cluster_capacity_providers" "this" {
  cluster_name = aws_ecs_cluster.this.name

  capacity_providers = ["FARGATE", "FARGATE_SPOT"]

  default_capacity_provider_strategy {
    capacity_provider = "FARGATE"
    weight            = 1
    base              = 1
  }
}

# ── IAM ───────────────────────────────────────────────────────────────────────

data "aws_iam_policy_document" "ecs_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "task_execution" {
  name               = "${local.name_prefix}-task-execution"
  assume_role_policy = data.aws_iam_policy_document.ecs_assume.json

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "task_execution" {
  role       = aws_iam_role.task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role" "task" {
  name               = "${local.name_prefix}-task"
  assume_role_policy = data.aws_iam_policy_document.ecs_assume.json

  tags = var.tags
}

resource "aws_iam_role_policy" "task_logs" {
  name = "cloudwatch-logs"
  role = aws_iam_role.task.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["logs:CreateLogStream", "logs:PutLogEvents"]
      Resource = "*"
    }]
  })
}

# ── CloudWatch Log Groups ─────────────────────────────────────────────────────

resource "aws_cloudwatch_log_group" "this" {
  for_each = local.services

  name              = "/ecs/${local.name_prefix}/${each.key}"
  retention_in_days = 30

  tags = var.tags
}

# ── Service Discovery ─────────────────────────────────────────────────────────

resource "aws_service_discovery_private_dns_namespace" "this" {
  name = local.sd_namespace
  vpc  = var.vpc_id

  tags = merge(var.tags, { Name = "${local.name_prefix}-sd-namespace" })
}

resource "aws_service_discovery_service" "this" {
  for_each = local.services

  name = each.key

  dns_config {
    namespace_id   = aws_service_discovery_private_dns_namespace.this.id
    routing_policy = "MULTIVALUE"

    dns_records {
      ttl  = 10
      type = "A"
    }
  }

  health_check_custom_config {
    failure_threshold = 1
  }
}

# ── Task Definitions ──────────────────────────────────────────────────────────

resource "aws_ecs_task_definition" "frontend" {
  family                   = "${local.name_prefix}-frontend"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = local.services.frontend.cpu
  memory                   = local.services.frontend.memory
  execution_role_arn       = aws_iam_role.task_execution.arn
  task_role_arn            = aws_iam_role.task.arn

  container_definitions = jsonencode([{
    name      = "frontend"
    image     = local.services.frontend.image
    essential = true

    portMappings = [{ containerPort = 3000, protocol = "tcp" }]

    environment = [
      { name = "PORT",        value = "3000" },
      { name = "BACKEND_URL", value = "http://backend.${local.sd_namespace}:5000" }
    ]

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.this["frontend"].name
        "awslogs-region"        = var.aws_region
        "awslogs-stream-prefix" = "frontend"
      }
    }

    healthCheck = {
      command     = ["CMD-SHELL", local.services.frontend.health_cmd]
      interval    = 30
      timeout     = 5
      retries     = 3
      startPeriod = local.services.frontend.start_period
    }
  }])

  tags = merge(var.tags, { Name = "${local.name_prefix}-frontend-td" })
}

resource "aws_ecs_task_definition" "backend" {
  family                   = "${local.name_prefix}-backend"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = local.services.backend.cpu
  memory                   = local.services.backend.memory
  execution_role_arn       = aws_iam_role.task_execution.arn
  task_role_arn            = aws_iam_role.task.arn

  container_definitions = jsonencode([{
    name      = "backend"
    image     = local.services.backend.image
    essential = true

    portMappings = [{ containerPort = 5000, protocol = "tcp" }]

    environment = [
      { name = "DB_HOST",     value = var.db_host },
      { name = "DB_PORT",     value = tostring(var.db_port) },
      { name = "DB_NAME",     value = var.db_name },
      { name = "DB_USER",     value = var.db_username },
      { name = "DB_PASSWORD", value = var.db_password },
      { name = "REDIS_HOST",  value = var.redis_host },
      { name = "REDIS_PORT",  value = tostring(var.redis_port) }
    ]

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.this["backend"].name
        "awslogs-region"        = var.aws_region
        "awslogs-stream-prefix" = "backend"
      }
    }

    healthCheck = {
      command     = ["CMD-SHELL", local.services.backend.health_cmd]
      interval    = 30
      timeout     = 5
      retries     = 3
      startPeriod = local.services.backend.start_period
    }
  }])

  tags = merge(var.tags, { Name = "${local.name_prefix}-backend-td" })
}

# ── ECS Services ──────────────────────────────────────────────────────────────

resource "aws_ecs_service" "frontend" {
  name            = "${local.name_prefix}-frontend"
  cluster         = aws_ecs_cluster.this.id
  task_definition = aws_ecs_task_definition.frontend.arn
  desired_count   = local.services.frontend.desired_count
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = var.private_subnet_ids
    security_groups  = [local.services.frontend.security_group]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = local.services.frontend.target_group
    container_name   = "frontend"
    container_port   = 3000
  }

  service_registries {
    registry_arn = aws_service_discovery_service.this["frontend"].arn
  }

  deployment_minimum_healthy_percent = 100
  deployment_maximum_percent         = 200

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  tags = merge(var.tags, { Name = "${local.name_prefix}-frontend-svc" })
}

resource "aws_ecs_service" "backend" {
  name            = "${local.name_prefix}-backend"
  cluster         = aws_ecs_cluster.this.id
  task_definition = aws_ecs_task_definition.backend.arn
  desired_count   = local.services.backend.desired_count
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = var.private_subnet_ids
    security_groups  = [local.services.backend.security_group]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = local.services.backend.target_group
    container_name   = "backend"
    container_port   = 5000
  }

  service_registries {
    registry_arn = aws_service_discovery_service.this["backend"].arn
  }

  deployment_minimum_healthy_percent = 100
  deployment_maximum_percent         = 200

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  tags = merge(var.tags, { Name = "${local.name_prefix}-backend-svc" })
}
