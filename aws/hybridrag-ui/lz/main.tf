locals {
  aws_region          = replace(lower(var.regions[0].name), "_", "-")
  ui                  = module.lz.ecs_apps["ui"]
  handoff_secret_name = local.ui.handoff_secret_name
  llm_enabled         = var.llm_secret_name != null
  llm_provider_from_env = {
    ANTHROPIC_API_KEY = "anthropic"
    OPENAI_API_KEY    = "openai"
    GEMINI_API_KEY    = "gemini"
    GROVE_API_KEY     = "grove"
  }
  llm_provider = local.llm_enabled ? lookup(local.llm_provider_from_env, var.llm_env_name, null) : null
  llm_container_env = merge(
    {
      CHAINLIT_DEMO_USERNAME = "demo"
      ENABLE_LLM             = local.llm_enabled ? "true" : "false"
    },
    local.llm_enabled && local.llm_provider != null ? { LLM_PROVIDER = local.llm_provider } : {}
  )
  llm_handoff_secrets = local.llm_enabled ? merge(
    { (var.llm_env_name) = data.aws_secretsmanager_secret_version.llm[0].secret_string },
    var.llm_env
  ) : {}
  container_secret_keys = concat(
    ["VOYAGE_API_KEY", "CHAINLIT_AUTH_SECRET", "CHAINLIT_DEMO_PASSWORD"],
    sort(keys(local.llm_handoff_secrets))
  )
}

module "lz" {
  source = "../../modules/lz"

  atlas_org_id                 = var.atlas_org_id
  cluster_name                 = var.cluster_name
  default_resource_name_prefix = var.default_resource_name_prefix
  regions                      = var.regions
  cluster_type                 = var.cluster_type
  shard_count                  = var.shard_count
  manual_scaling               = var.manual_scaling
  vpc_config                   = var.vpc_config
  atlas_integrations           = var.atlas_integrations
  ecr_repositories             = var.ecr_repositories
  http_edges                   = var.http_edges
  ecs_apps                     = var.ecs_apps
  tags                         = var.tags
  public_debug_access          = var.public_debug_access
}

module "voyage_api_key" {
  source = "./modules/voyage_api_key"

  project_id = module.lz.atlas.project_id
  key_name   = var.voyage_key_name
}

resource "random_password" "chainlit_auth" {
  length  = 64
  special = false
}

resource "random_password" "chainlit_demo" {
  length  = 16
  special = false
}

resource "aws_secretsmanager_secret" "chainlit_auth" {
  region = local.aws_region
  name   = "${local.ui.name}-chainlit-auth"
  tags   = var.tags
}

resource "aws_secretsmanager_secret_version" "chainlit_auth" {
  region        = local.aws_region
  secret_id     = aws_secretsmanager_secret.chainlit_auth.id
  secret_string = random_password.chainlit_auth.result
}

resource "aws_secretsmanager_secret" "chainlit_demo" {
  region = local.aws_region
  name   = "${local.ui.name}-demo-password"
  tags   = var.tags
}

resource "aws_secretsmanager_secret_version" "chainlit_demo" {
  region        = local.aws_region
  secret_id     = aws_secretsmanager_secret.chainlit_demo.id
  secret_string = random_password.chainlit_demo.result
}

data "aws_secretsmanager_secret_version" "llm" {
  count     = local.llm_enabled ? 1 : 0
  secret_id = var.llm_secret_name
}

resource "aws_secretsmanager_secret" "handoff" {
  region = local.aws_region
  name   = local.handoff_secret_name
  tags   = var.tags
}

resource "aws_secretsmanager_secret_version" "handoff" {
  region    = local.aws_region
  secret_id = aws_secretsmanager_secret.handoff.id
  secret_string = jsonencode(merge({
    aws_region                      = local.ui.aws_region
    name                            = local.ui.name
    private_subnet_ids              = local.ui.network.private_subnet_ids
    ecs_security_group_id           = local.ui.network.ecs_security_group_id
    ecs_task_role_arn               = local.ui.iam.task_role_arn
    ecs_task_execution_role_arn     = local.ui.iam.task_execution_role_arn
    mongo_private_connection_string = local.ui.mongo.connection_string
    app_database_name               = local.ui.mongo.database_name
    ecr_repository_url              = local.ui.ecr_repository_url
    alb_listener_arn                = local.ui.routing.listener_arn
    listener_priority               = local.ui.routing.listener_priority
    path_pattern                    = local.ui.routing.path_pattern
    host_header                     = local.ui.routing.host_header
    container_port                  = local.ui.routing.container_port
    health_check_path               = local.ui.routing.health_check_path
    origin_header_name              = local.ui.routing.origin_header_name
    origin_header_value             = module.lz.http_edge_origin_header_values[local.ui.routing.edge]
    task_cpu                        = local.ui.task_cpu
    task_memory                     = local.ui.task_memory
    container_env_vars              = local.llm_container_env
    container_secret_keys           = local.container_secret_keys
    VOYAGE_API_KEY                  = module.voyage_api_key.api_key
    VOYAGE_BASE_URL                 = module.voyage_api_key.voyage_base_url
    CHAINLIT_AUTH_SECRET            = random_password.chainlit_auth.result
    CHAINLIT_DEMO_PASSWORD          = random_password.chainlit_demo.result
  }, local.llm_handoff_secrets))
}
