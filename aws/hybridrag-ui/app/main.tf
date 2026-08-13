module "ecs_service" {
  source = "../../modules/ecs-service"

  handoff_secret_name = var.handoff_secret_name
  image_tag           = var.image_tag
  tags                = var.tags
}
