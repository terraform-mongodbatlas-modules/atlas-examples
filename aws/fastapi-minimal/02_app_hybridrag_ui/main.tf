module "ecs" {
  source = "../02_app_ecs/app"

  handoff_secret_name               = var.handoff_secret_name
  image_tag                         = var.image_tag
  tags                              = var.tags
  wait_for_steady_state             = var.wait_for_steady_state
  health_check_grace_period_seconds = var.health_check_grace_period_seconds
  deployment_timeout                = var.deployment_timeout
}
