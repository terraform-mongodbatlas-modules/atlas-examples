locals {
  aws_region      = replace(lower(var.regions[0].name), "_", "-")
  ui              = module.lz.ecs_apps["ui"]
  app_secret_name = local.ui.runtime_secret_name
  llm_enabled     = var.llm_secret_name != null
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
  llm_app_secrets = local.llm_enabled ? merge(
    { (var.llm_env_name) = data.aws_secretsmanager_secret_version.llm[0].secret_string },
    var.llm_env
  ) : {}
  container_secret_keys = concat(
    ["VOYAGE_API_KEY", "CHAINLIT_AUTH_SECRET", "CHAINLIT_DEMO_PASSWORD"],
    sort(keys(local.llm_app_secrets))
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

resource "aws_secretsmanager_secret" "app" {
  region = local.aws_region
  name   = local.app_secret_name
  tags   = var.tags
}

resource "aws_secretsmanager_secret_version" "app" {
  region    = local.aws_region
  secret_id = aws_secretsmanager_secret.app.id
  secret_string = jsonencode(merge({
    name               = local.ui.name
    aws_region         = local.ui.aws_region
    ecr_repository_url = local.ui.ecr_repository_url
    network            = local.ui.network
    iam                = local.ui.iam
    mongo              = local.ui.mongo
    routing = merge(local.ui.routing, {
      health_check_path   = "/"
      origin_header_value = module.lz.http_edge_origin_header_values[local.ui.routing.edge]
    })
    container = {
      env         = local.llm_container_env
      secret_keys = local.container_secret_keys
    }
    VOYAGE_API_KEY         = module.voyage_api_key.api_key
    VOYAGE_BASE_URL        = module.voyage_api_key.voyage_base_url
    CHAINLIT_AUTH_SECRET   = random_password.chainlit_auth.result
    CHAINLIT_DEMO_PASSWORD = random_password.chainlit_demo.result
  }, local.llm_app_secrets))
}
