data "aws_secretsmanager_secret" "handoff" {
  name = var.handoff_secret_name
}

data "aws_secretsmanager_secret_version" "handoff" {
  secret_id = data.aws_secretsmanager_secret.handoff.id
}

locals {
  handoff = jsondecode(nonsensitive(data.aws_secretsmanager_secret_version.handoff.secret_string))

  aws_region                      = local.handoff.aws_region
  name                            = local.handoff.name
  private_subnet_ids              = local.handoff.private_subnet_ids
  ecs_security_group_id           = local.handoff.ecs_security_group_id
  ecs_task_role_arn               = local.handoff.ecs_task_role_arn
  ecs_task_execution_role_arn     = local.handoff.ecs_task_execution_role_arn
  mongo_private_connection_string = local.handoff.mongo_private_connection_string
  app_database_name               = local.handoff.app_database_name
  ecr_repository_url              = local.handoff.ecr_repository_url
  alb_listener_arn                = local.handoff.alb_listener_arn
  listener_priority               = local.handoff.listener_priority
  path_pattern                    = try(local.handoff.path_pattern, [])
  host_header                     = try(local.handoff.host_header, [])
  container_port                  = try(local.handoff.container_port, 8000)
  health_check_path               = try(local.handoff.health_check_path, "/health")
  container_env_vars              = try(local.handoff.container_env_vars, {})
  container_secret_keys           = try(local.handoff.container_secret_keys, [])
  origin_header_name              = try(local.handoff.origin_header_name, "")
  origin_header_value             = try(local.handoff.origin_header_value, "")
  task_cpu                        = try(local.handoff.task_cpu, "512")
  task_memory                     = try(local.handoff.task_memory, "1024")

  image_uri      = "${local.ecr_repository_url}:${var.image_tag}"
  log_group_name = "/ecs/${local.name}"
  handoff_arn    = data.aws_secretsmanager_secret.handoff.arn
}

data "aws_subnet" "first_private" {
  region = local.aws_region
  id     = local.private_subnet_ids[0]
}

resource "aws_cloudwatch_log_group" "ecs" {
  region            = local.aws_region
  name              = local.log_group_name
  retention_in_days = 7
  tags              = var.tags
}

resource "aws_ecs_cluster" "this" {
  region = local.aws_region
  name   = local.name
  tags   = var.tags
}

resource "aws_lb_target_group" "this" {
  region      = local.aws_region
  name        = local.name
  port        = local.container_port
  protocol    = "HTTP"
  vpc_id      = data.aws_subnet.first_private.vpc_id
  target_type = "ip"

  health_check {
    path = local.health_check_path
  }

  tags = var.tags
}

resource "aws_lb_listener_rule" "this" {
  region       = local.aws_region
  listener_arn = local.alb_listener_arn
  priority     = local.listener_priority

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.this.arn
  }

  dynamic "condition" {
    for_each = length(local.path_pattern) > 0 ? [1] : []
    content {
      path_pattern {
        values = local.path_pattern
      }
    }
  }

  dynamic "condition" {
    for_each = length(local.host_header) > 0 ? [1] : []
    content {
      host_header {
        values = local.host_header
      }
    }
  }

  dynamic "condition" {
    for_each = local.origin_header_name != "" ? [1] : []
    content {
      http_header {
        http_header_name = local.origin_header_name
        values           = [local.origin_header_value]
      }
    }
  }
}

resource "aws_ecs_task_definition" "this" {
  region                   = local.aws_region
  family                   = local.name
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = local.task_cpu
  memory                   = local.task_memory
  execution_role_arn       = local.ecs_task_execution_role_arn
  task_role_arn            = local.ecs_task_role_arn

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "ARM64"
  }

  container_definitions = jsonencode([{
    name      = local.name
    image     = local.image_uri
    essential = true
    portMappings = [{
      containerPort = local.container_port
      protocol      = "tcp"
    }]
    environment = concat(
      [
        { name = "MONGO_URL", value = local.mongo_private_connection_string },
        { name = "DB_NAME", value = local.app_database_name },
      ],
      [for k, v in local.container_env_vars : { name = k, value = v }]
    )
    secrets = [
      for key in local.container_secret_keys : {
        name      = key
        valueFrom = "${local.handoff_arn}:${key}::"
      }
    ]
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.ecs.name
        "awslogs-region"        = local.aws_region
        "awslogs-stream-prefix" = "ecs"
      }
    }
  }])

  tags = var.tags
}

resource "aws_ecs_service" "this" {
  region          = local.aws_region
  name            = local.name
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
    subnets          = local.private_subnet_ids
    security_groups  = [local.ecs_security_group_id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.this.arn
    container_name   = local.name
    container_port   = local.container_port
  }

  depends_on = [aws_lb_listener_rule.this]

  tags = var.tags
}
