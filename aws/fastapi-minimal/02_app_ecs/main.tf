data "aws_secretsmanager_secret_version" "handoff" {
  count     = var.handoff_secret_name != null ? 1 : 0
  secret_id = var.handoff_secret_name
}

locals {
  handoff = var.handoff_secret_name != null ? jsondecode(nonsensitive(data.aws_secretsmanager_secret_version.handoff[0].secret_string)) : null

  aws_region                      = coalesce(try(local.handoff.aws_region, null), var.aws_region)
  name_prefix                     = coalesce(try(local.handoff.name_prefix, null), var.name_prefix, "fastapi-minimal")
  private_subnet_ids              = coalesce(try(local.handoff.private_subnet_ids, null), var.private_subnet_ids)
  ecs_security_group_id           = coalesce(try(local.handoff.ecs_security_group_id, null), var.ecs_security_group_id)
  ecs_task_role_arn               = coalesce(try(local.handoff.ecs_task_role_arn, null), var.ecs_task_role_arn)
  ecs_task_execution_role_arn     = coalesce(try(local.handoff.ecs_task_execution_role_arn, null), var.ecs_task_execution_role_arn)
  mongo_private_connection_string = coalesce(try(local.handoff.mongo_private_connection_string, null), var.mongo_private_connection_string)
  app_database_name               = coalesce(try(local.handoff.app_database_name, null), var.app_database_name, "test")
  ecr_repository_url              = coalesce(try(local.handoff.ecr_repository_url, null), var.ecr_repository_url)
  alb_listener_arn                = coalesce(try(local.handoff.alb_listener_arn, null), var.alb_listener_arn)
  alb_dns_name                    = coalesce(try(local.handoff.alb_dns_name, null), var.alb_dns_name)
  listener_priority               = coalesce(try(local.handoff.listener_priority, null), var.listener_priority)
  path_pattern                    = coalesce(try(local.handoff.path_pattern, null), var.path_pattern, [])
  host_header                     = coalesce(try(local.handoff.host_header, null), var.host_header, [])
  container_port                  = coalesce(try(local.handoff.container_port, null), var.container_port, 8000)
  health_check_path               = coalesce(try(local.handoff.health_check_path, null), var.health_check_path, "/health")
  container_env_vars              = coalesce(try(local.handoff.container_env_vars, null), var.container_env_vars, {})
  container_secret_env_vars       = coalesce(try(local.handoff.container_secret_env_vars, null), var.container_secret_env_vars, {})

  name           = local.name_prefix
  image_uri      = "${local.ecr_repository_url}:${var.image_tag}"
  log_group_name = "/ecs/${local.name}"
  smoke_test_url = "http://${local.alb_dns_name}${local.health_check_path}"
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
}

resource "aws_ecs_task_definition" "this" {
  region                   = local.aws_region
  family                   = local.name
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = "512"
  memory                   = "1024"
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
      for k, v in local.container_secret_env_vars : { name = k, valueFrom = v }
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
