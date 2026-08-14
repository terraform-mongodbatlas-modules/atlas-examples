data "aws_secretsmanager_secret" "app" {
  name = var.app_secret_name
}

data "aws_secretsmanager_secret_version" "app" {
  secret_id = data.aws_secretsmanager_secret.app.id
}

locals {
  app = jsondecode(nonsensitive(data.aws_secretsmanager_secret_version.app.secret_string))
}

module "ecs_service" {
  source = "../../modules/ecs-service"

  name               = local.app.name
  aws_region         = local.app.aws_region
  ecr_repository_url = local.app.ecr_repository_url
  network            = local.app.network
  iam                = local.app.iam
  routing            = local.app.routing
  container = merge(local.app.container, {
    secret_arn = data.aws_secretsmanager_secret.app.arn
  })
  task_cpu    = var.task_cpu
  task_memory = var.task_memory
  image_tag   = var.image_tag
  tags        = var.tags
}
