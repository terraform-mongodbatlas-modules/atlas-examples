# Hybrid Search UI: stack one of two. This stack creates the Atlas project,
# cluster, AWS app platform (VPC, endpoints, roles, ECR, HTTP edge), and the
# Secrets Manager secret the app stack in `../app/` reads.

locals {
  # --- Regions ----------------------------------------------------------------
  regions_resolved = [
    for r in var.regions : {
      aws_name   = replace(lower(r.name), "_", "-")
      atlas_name = upper(replace(replace(lower(r.name), "_", "-"), "-", "_"))
      node_count = r.node_count
    }
  ]
  aws_region  = local.regions_resolved[0].aws_name
  aws_regions = [for r in local.regions_resolved : r.aws_name]

  # --- ECS apps ---------------------------------------------------------------
  ecs_apps = {
    for k, v in var.ecs_apps : k => {
      name                = coalesce(v.name, k)
      aws_region          = coalesce(v.aws_region, local.aws_region)
      runtime_secret_name = "${coalesce(v.name, k)}-app"
      roles               = v.roles
    }
  }
  app_aws_regions = toset([for app in local.ecs_apps : app.aws_region])
  ui              = module.app_platform.ecs_apps["ui"]
  # The app's roles grant carries the database name, so MONGODB_DATABASE cannot
  # drift from the IAM user's grant.
  ui_database     = local.ecs_apps["ui"].roles[0].database_name
  app_secret_name = local.ui.runtime_secret_name

  # --- Atlas AWS integrations -------------------------------------------------
  kms_primary_region = lower(replace(coalesce(
    var.atlas_integrations.encryption.create_kms_key.region,
    local.aws_region
  ), "_", "-"))
  kms_replica_regions = (
    var.atlas_integrations.encryption.create_kms_key.multi_region
    ? (
      var.atlas_integrations.encryption.create_kms_key.replica_regions != null
      ? var.atlas_integrations.encryption.create_kms_key.replica_regions
      : toset([for r in local.aws_regions : r if r != local.kms_primary_region])
    )
    : toset([])
  )

  atlas_aws_encryption = {
    enabled = var.atlas_integrations.encryption.enabled
    private_endpoint_regions = (
      var.atlas_integrations.encryption.enabled && !var.atlas_integrations.encryption.skip_private_endpoints
      ? local.aws_regions
      : []
    )
    kms_key_arn = (
      var.atlas_integrations.encryption.enabled
      ? var.atlas_integrations.encryption.kms_key_arn
      : null
    )
    region = (
      var.atlas_integrations.encryption.enabled && var.atlas_integrations.encryption.kms_key_arn == null
      ? local.kms_primary_region
      : null
    )
    create_kms_key = (
      var.atlas_integrations.encryption.enabled && var.atlas_integrations.encryption.kms_key_arn == null
      ? {
        enabled                 = true
        deletion_window_in_days = var.atlas_integrations.encryption.create_kms_key.deletion_window_in_days
        enable_key_rotation     = var.atlas_integrations.encryption.create_kms_key.enable_key_rotation
        multi_region            = var.atlas_integrations.encryption.create_kms_key.multi_region
        replica_regions         = local.kms_replica_regions
      }
      : null
    )
  }

  atlas_aws_log_integration = {
    enabled = var.atlas_integrations.log_integration.enabled
    create_s3_bucket = (
      var.atlas_integrations.log_integration.enabled
      ? {
        enabled         = true
        force_destroy   = var.atlas_integrations.s3_force_destroy
        name_prefix     = "${var.default_resource_name_prefix}-logs-"
        expiration_days = var.atlas_integrations.log_integration.expiration_days
      }
      : null
    )
    integrations = (
      var.atlas_integrations.log_integration.enabled
      ? var.atlas_integrations.log_integration.integrations
      : null
    )
  }

  atlas_aws_backup_export = {
    enabled = var.atlas_integrations.backup_export.enabled
    create_s3_bucket = (
      var.atlas_integrations.backup_export.enabled
      ? {
        enabled         = true
        force_destroy   = var.atlas_integrations.s3_force_destroy
        name_prefix     = "${var.default_resource_name_prefix}-backup-"
        expiration_days = var.atlas_integrations.backup_export.expiration_days
      }
      : null
    )
  }

  # --- Mongo connection strings ------------------------------------------------
  # PrivateLink SRV per region when Atlas publishes it, else the standard SRV.
  # Appends IAM auth query params; the app authenticates with MONGODB-AWS.
  mongo_private_connection_string = try(coalesce(
    try(module.atlas_cluster.connection_strings.private_endpoint[0].srv_connection_string, ""),
    try(module.atlas_cluster.connection_strings.private_srv, ""),
    module.atlas_cluster.connection_strings.standard_srv
    ), "NO_CONNECTION_STRING_AVAILABLE"
  )
  mongo_private_connection_string_uses_standard_srv = (
    local.mongo_private_connection_string == module.atlas_cluster.connection_strings.standard_srv
  )
  mongo_private_connection_string_unavailable = (
    local.mongo_private_connection_string == "NO_CONNECTION_STRING_AVAILABLE"
  )

  aws_to_atlas_region = {
    for r in local.regions_resolved : r.aws_name => r.atlas_name
  }
  mongo_private_srv_by_atlas_region = merge([
    for pe in try(module.atlas_cluster.connection_strings.private_endpoint, []) : {
      for ep in try(pe.endpoints, []) :
      ep.region => pe.srv_connection_string
      if try(pe.srv_connection_string, "") != ""
    }
  ]...)
  mongo_private_connection_strings_by_region = {
    for region in local.app_aws_regions : region => coalesce(
      try(local.mongo_private_srv_by_atlas_region[local.aws_to_atlas_region[region]], ""),
      local.mongo_private_connection_string
    )
  }

  mongo_iam_auth_query = "authSource=%24external&authMechanism=MONGODB-AWS"

  # The app's URI. The module deliberately does not return it: it derives from
  # module.atlas_cluster, which depends_on module.app_platform, so routing it
  # back through the module would close a cycle.
  mongo_iam_connection_strings_by_region = {
    for region, srv in local.mongo_private_connection_strings_by_region :
    region => (
      srv == "" || srv == "NO_CONNECTION_STRING_AVAILABLE"
      ? srv
      : strcontains(srv, "?")
      ? "${srv}&${local.mongo_iam_auth_query}"
      : "${srv}/?${local.mongo_iam_auth_query}"
    )
  }

  public_debug_password = var.public_debug_access != null ? coalesce(
    try(var.public_debug_access.password, null),
    try(random_password.public_debug[0].result, null)
  ) : null

  public_debug_connection_string = var.public_debug_access != null ? format(
    "mongodb+srv://%s:%s@%s/?authSource=admin",
    urlencode(var.public_debug_access.username),
    urlencode(local.public_debug_password),
    trimprefix(module.atlas_cluster.connection_strings.standard_srv, "mongodb+srv://")
  ) : null
}

check "mongo_private_connection_string_standard_srv_fallback" {
  assert {
    condition     = !local.mongo_private_connection_string_uses_standard_srv
    error_message = <<-EOT
      mongo_private_connection_string fell back to standard_srv (non-PrivateLink).
      Atlas did not publish private_endpoint or private_srv SRV connection strings yet.
      ECS apps will receive the public Atlas SRV; traffic may not route over PrivateLink.
    EOT
  }
}

check "mongo_private_connection_string_unavailable" {
  assert {
    condition     = !local.mongo_private_connection_string_unavailable
    error_message = <<-EOT
      mongo_private_connection_string is NO_CONNECTION_STRING_AVAILABLE.
      Atlas did not publish private_endpoint, private_srv, or standard_srv connection strings.
      This can happen when the cluster is paused; otherwise it should not occur (cluster state: ${module.atlas_cluster.state_name}).
    EOT
  }
}

# --- LLM ----------------------------------------------------------------------
# module.llm resolves the provider, container env, secret keys, and the Bedrock
# task-role policy. It creates no resources.

module "llm" {
  source = "../../modules/llm"

  enable_llm   = var.enable_llm
  llm_provider = var.llm_provider
  secret_name  = var.llm_secret_name
  secret_value = try(data.aws_secretsmanager_secret_version.llm[0].secret_string, null)
  env_name     = var.llm_env_name
  env          = var.llm_env
  aws_region   = local.aws_region
}

data "aws_secretsmanager_secret_version" "llm" {
  count     = var.enable_llm && var.llm_secret_name != null ? 1 : 0
  secret_id = var.llm_secret_name
}

# --- Atlas and AWS app platform ----------------------------------------------

module "app_platform" {
  source = "../../modules/app-platform"

  default_resource_name_prefix = var.default_resource_name_prefix
  regions                      = var.regions
  tags                         = var.tags
  ecr_repositories             = var.ecr_repositories
  # bedrock_runtime_endpoint defaults to the provider inference: a Bedrock
  # provider needs the private endpoint, a keyed provider does not.
  vpc_config = merge(var.vpc_config, {
    bedrock_runtime_endpoint = module.llm.bedrock.enabled
  })
  http_edges = {
    for k, v in var.http_edges : k => {
      waf = {
        enabled                     = v.waf.enabled
        common_rule_set_count_rules = distinct(concat(v.waf.common_rule_set_count_rules, local.chainlit_waf_count_rules))
      }
    }
  }
  ecs_apps = {
    for k, app in var.ecs_apps : k => {
      name             = app.name
      ecr_key          = app.ecr_key
      aws_region       = app.aws_region
      primary_database = app.primary_database
      internet_egress  = app.internet_egress
      roles            = app.roles
      # app_platform validates the rest; only routing collapses when there is
      # no HTTP edge.
      routing             = length(var.http_edges) == 0 ? null : app.routing
      extra_task_policies = module.llm.task_policy_jsons
    }
  }
}

locals {
  # CRS SizeRestrictions_BODY blocks bodies over 8 KB. Chainlit POST /project/file
  # is a multipart upload (NIST PDFs, OWASP markdown) and also trips BODY XSS/RFI/LFI.
  chainlit_waf_count_rules = [
    "SizeRestrictions_BODY",
    "CrossSiteScripting_BODY",
    "GenericRFI_BODY",
    "GenericLFI_BODY",
    "EC2MetaDataSSRF_BODY",
  ]

  # App env is not LLM-provider logic, so it lives here next to MONGODB_*.
  # TOP_K caps $rankFusion hits before the LLM answers; CHUNK_MAX_TOKENS caps the
  # chunk size the app writes. Change them here and re-apply lz, then app.
  app_env = {
    CHAINLIT_DEMO_USERNAME = "demo"
    MONGODB_DATABASE       = local.ui_database
    MONGODB_URI            = local.mongo_iam_connection_strings_by_region[local.ui.aws_region]
    SKIP_INDEX_CREATION    = "true"
    TOP_K                  = "20"
    CHUNK_MAX_TOKENS       = "512"
    AUTOEMBED_MODEL        = var.autoembed_model
  }
  container_env         = merge(local.app_env, module.llm.env)
  container_secret_keys = module.llm.secret_keys
}

# --- App secret ---------------------------------------------------------------
# The app stack reads this secret. MONGODB_URI is the IAM PrivateLink URI for
# the app's region; the container authenticates with MONGODB-AWS.

resource "random_password" "chainlit_auth" {
  length  = 64
  special = false
}

resource "random_password" "chainlit_demo" {
  length  = 16
  special = false
}

resource "aws_secretsmanager_secret" "app" {
  region                  = local.aws_region
  name                    = local.app_secret_name
  tags                    = var.tags
  recovery_window_in_days = 0
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
    routing = local.ui.routing == null ? null : merge(local.ui.routing, {
      health_check_path   = "/"
      origin_header_value = module.app_platform.http_edge_origin_header_values[local.ui.routing.edge]
    })
    container = {
      env         = local.container_env
      secret_keys = local.container_secret_keys
    }
    CHAINLIT_AUTH_SECRET   = random_password.chainlit_auth.result
    CHAINLIT_DEMO_PASSWORD = random_password.chainlit_demo.result
  }, module.llm.secrets))
}
