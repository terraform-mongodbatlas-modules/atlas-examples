module "app" {
  source = "./app"

  handoff_secret_name               = var.handoff_secret_name
  aws_region                        = var.aws_region
  private_subnet_ids                = var.private_subnet_ids
  ecs_security_group_id             = var.ecs_security_group_id
  ecs_task_role_arn                 = var.ecs_task_role_arn
  ecs_task_execution_role_arn       = var.ecs_task_execution_role_arn
  mongo_private_connection_string   = var.mongo_private_connection_string
  ecr_repository_url                = var.ecr_repository_url
  alb_listener_arn                  = var.alb_listener_arn
  alb_dns_name                      = var.alb_dns_name
  listener_priority                 = var.listener_priority
  path_pattern                      = var.path_pattern
  host_header                       = var.host_header
  container_port                    = var.container_port
  health_check_path                 = var.health_check_path
  container_env_vars                = var.container_env_vars
  container_secret_env_vars         = var.container_secret_env_vars
  wait_for_steady_state             = var.wait_for_steady_state
  deployment_timeout                = var.deployment_timeout
  health_check_grace_period_seconds = var.health_check_grace_period_seconds
  name_prefix                       = var.name_prefix
  image_tag                         = var.image_tag
  app_database_name                 = var.app_database_name
  tags                              = var.tags
}
