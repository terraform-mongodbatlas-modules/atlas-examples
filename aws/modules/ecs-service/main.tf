locals {
  image_uri      = "${var.ecr_repository_url}:${var.image_tag}"
  log_group_name = "/ecs/${var.name}"
}

data "aws_subnet" "first_private" {
  region = var.aws_region
  id     = var.network.private_subnet_ids[0]
}

resource "aws_cloudwatch_log_group" "ecs" {
  region            = var.aws_region
  name              = local.log_group_name
  retention_in_days = 7
  tags              = var.tags
}

resource "aws_ecs_cluster" "this" {
  region = var.aws_region
  name   = var.name
  tags   = var.tags
}

resource "aws_lb_target_group" "this" {
  region      = var.aws_region
  name        = var.name
  port        = var.routing.container_port
  protocol    = "HTTP"
  vpc_id      = data.aws_subnet.first_private.vpc_id
  target_type = "ip"

  health_check {
    path = var.routing.health_check_path
  }

  tags = var.tags
}

resource "aws_lb_listener_rule" "this" {
  region       = var.aws_region
  listener_arn = var.routing.listener_arn
  priority     = var.routing.listener_priority

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.this.arn
  }

  dynamic "condition" {
    for_each = length(var.routing.path_pattern) > 0 ? [1] : []
    content {
      path_pattern {
        values = var.routing.path_pattern
      }
    }
  }

  dynamic "condition" {
    for_each = length(var.routing.host_header) > 0 ? [1] : []
    content {
      host_header {
        values = var.routing.host_header
      }
    }
  }

  dynamic "condition" {
    for_each = var.routing.origin_header_name != "" ? [1] : []
    content {
      http_header {
        http_header_name = var.routing.origin_header_name
        values           = [var.routing.origin_header_value]
      }
    }
  }
}

resource "aws_ecs_task_definition" "this" {
  region                   = var.aws_region
  family                   = var.name
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.task_cpu
  memory                   = var.task_memory
  execution_role_arn       = var.iam.task_execution_role_arn
  task_role_arn            = var.iam.task_role_arn

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "ARM64"
  }

  container_definitions = jsonencode([{
    name      = var.name
    image     = local.image_uri
    essential = true
    portMappings = [{
      containerPort = var.routing.container_port
      protocol      = "tcp"
    }]
    environment = concat(
      [
        { name = "MONGO_URL", value = var.mongo.connection_string },
        { name = "DB_NAME", value = var.mongo.database_name },
      ],
      [for k, v in var.container.env : { name = k, value = v }]
    )
    secrets = [
      for key in var.container.secret_keys : {
        name      = key
        valueFrom = "${var.container.secret_arn}:${key}::"
      }
    ]
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.ecs.name
        "awslogs-region"        = var.aws_region
        "awslogs-stream-prefix" = "ecs"
      }
    }
  }])

  tags = var.tags
}

resource "aws_ecs_service" "this" {
  region          = var.aws_region
  name            = var.name
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
    subnets          = var.network.private_subnet_ids
    security_groups  = [var.network.ecs_security_group_id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.this.arn
    container_name   = var.name
    container_port   = var.routing.container_port
  }

  depends_on = [aws_lb_listener_rule.this]

  tags = var.tags
}
