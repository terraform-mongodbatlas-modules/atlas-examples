data "aws_secretsmanager_secret" "handoff" {
  name = var.handoff_secret_name
}

data "aws_secretsmanager_secret_version" "handoff" {
  secret_id = data.aws_secretsmanager_secret.handoff.id
}

locals {
  handoff = jsondecode(nonsensitive(data.aws_secretsmanager_secret_version.handoff.secret_string))
}

module "ecs_service" {
  source = "../../modules/ecs-service"

  handoff = merge(local.handoff, {
    secret_arn = data.aws_secretsmanager_secret.handoff.arn
  })
  image_tag = var.image_tag
  tags      = var.tags
}
