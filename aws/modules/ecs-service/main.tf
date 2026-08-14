locals {
  image_uri      = "${var.handoff.ecr_repository_url}:${var.image_tag}"
  log_group_name = "/ecs/${var.handoff.name}"
}

data "aws_subnet" "first_private" {
  region = var.handoff.aws_region
  id     = var.handoff.private_subnet_ids[0]
}

resource "aws_cloudwatch_log_group" "ecs" {
  region            = var.handoff.aws_region
  name              = local.log_group_name
  retention_in_days = 7
  tags              = var.tags
}

resource "aws_ecs_cluster" "this" {
  region = var.handoff.aws_region
  name   = var.handoff.name
  tags   = var.tags
}

resource "aws_lb_target_group" "this" {
  region      = var.handoff.aws_region
  name        = var.handoff.name
  port        = var.handoff.container_port
  protocol    = "HTTP"
  vpc_id      = data.aws_subnet.first_private.vpc_id
  target_type = "ip"

  health_check {
    path = var.handoff.health_check_path
  }

  tags = var.tags
}

resource "aws_lb_listener_rule" "this" {
  region       = var.handoff.aws_region
  listener_arn = var.handoff.alb_listener_arn
  priority     = var.handoff.listener_priority

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.this.arn
  }

  dynamic "condition" {
    for_each = length(var.handoff.path_pattern) > 0 ? [1] : []
    content {
      path_pattern {
        values = var.handoff.path_pattern
      }
    }
  }

  dynamic "condition" {
    for_each = length(var.handoff.host_header) > 0 ? [1] : []
    content {
      host_header {
        values = var.handoff.host_header
      }
    }
  }

  dynamic "condition" {
    for_each = var.handoff.origin_header_name != "" ? [1] : []
    content {
      http_header {
        http_header_name = var.handoff.origin_header_name
        values           = [var.handoff.origin_header_value]
      }
    }
  }
}

resource "aws_ecs_task_definition" "this" {
  region                   = var.handoff.aws_region
  family                   = var.handoff.name
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.handoff.task_cpu
  memory                   = var.handoff.task_memory
  execution_role_arn       = var.handoff.ecs_task_execution_role_arn
  task_role_arn            = var.handoff.ecs_task_role_arn

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "ARM64"
  }

  container_definitions = jsonencode([{
    name      = var.handoff.name
    image     = local.image_uri
    essential = true
    portMappings = [{
      containerPort = var.handoff.container_port
      protocol      = "tcp"
    }]
    environment = concat(
      [
        { name = "MONGO_URL", value = var.handoff.mongo_private_connection_string },
        { name = "DB_NAME", value = var.handoff.app_database_name },
      ],
      [for k, v in var.handoff.container_env_vars : { name = k, value = v }]
    )
    secrets = [
      for key in var.handoff.container_secret_keys : {
        name      = key
        valueFrom = "${var.handoff.secret_arn}:${key}::"
      }
    ]
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.ecs.name
        "awslogs-region"        = var.handoff.aws_region
        "awslogs-stream-prefix" = "ecs"
      }
    }
  }])

  tags = var.tags
}

resource "aws_ecs_service" "this" {
  region          = var.handoff.aws_region
  name            = var.handoff.name
  cluster         = aws_ecs_cluster.this.id
  task_definition = aws_ecs_task_definition.this.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  wait_for_steady_state             = var.wait_for_steady_state
  health_check_grace_period_seconds = var.health_check_grace_period_seconds

  timeouts {
    create = var.deployment_timeout
    update = var.deployment_timeout
    delete = var.deployment_timeout
  }

  network_configuration {
    subnets          = var.handoff.private_subnet_ids
    security_groups  = [var.handoff.ecs_security_group_id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.this.arn
    container_name   = var.handoff.name
    container_port   = var.handoff.container_port
  }

  depends_on = [aws_lb_listener_rule.this]

  tags = var.tags
}
