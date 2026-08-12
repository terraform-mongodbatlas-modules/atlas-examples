locals {
  managed_vpc_regions = var.vpc_config.create ? toset(local.aws_regions) : toset([])
  vpc_cidr_by_region = {
    for i, region in local.aws_regions :
    region => coalesce(
      try(var.vpc_config.by_region[region].cidr, null),
      cidrsubnet(var.vpc_config.base_cidr, 8, i)
    )
  }
  vpc_az_count_by_region = {
    for region in local.aws_regions :
    region => coalesce(try(var.vpc_config.by_region[region].az_count, null), var.vpc_config.az_count)
  }
  privatelink_subnet_ids_by_region = var.vpc_config.create ? {
    for region, mod in module.vpc : region => mod.private_subnets
    } : {
    for region, cfg in var.vpc_config.by_region : region => cfg.private_subnet_ids
  }
  vpc_id                  = var.vpc_config.create ? module.vpc[local.aws_region].vpc_id : var.vpc_config.by_region[local.aws_region].vpc_id
  private_subnet_ids      = var.vpc_config.create ? module.vpc[local.aws_region].private_subnets : var.vpc_config.by_region[local.aws_region].private_subnet_ids
  vpc_cidr_block          = var.vpc_config.create ? module.vpc[local.aws_region].vpc_cidr_block : var.vpc_config.by_region[local.aws_region].vpc_cidr_block
  private_route_table_ids = var.vpc_config.create ? module.vpc[local.aws_region].private_route_table_ids : var.vpc_config.by_region[local.aws_region].private_route_table_ids

  app_aws_regions = setunion(
    toset([for app in local.lambda_apps : app.aws_region]),
    toset([for app in local.ecs_apps : app.aws_region])
  )
  app_network = {
    for region in local.app_aws_regions : region => {
      vpc_id             = var.vpc_config.create ? module.vpc[region].vpc_id : var.vpc_config.by_region[region].vpc_id
      private_subnet_ids = var.vpc_config.create ? module.vpc[region].private_subnets : var.vpc_config.by_region[region].private_subnet_ids
      public_subnet_ids = var.vpc_config.create ? (
        contains(local.ecs_alb_regions, region) ? module.vpc[region].public_subnets : []
        ) : (
        try(var.vpc_config.by_region[region].public_subnet_ids, [])
      )
      vpc_cidr_block          = var.vpc_config.create ? module.vpc[region].vpc_cidr_block : var.vpc_config.by_region[region].vpc_cidr_block
      private_route_table_ids = var.vpc_config.create ? module.vpc[region].private_route_table_ids : var.vpc_config.by_region[region].private_route_table_ids
    }
  }

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

  # Per-app-region PrivateLink SRV for 02_app_* handoff (MONGO_URL).
  #
  # Two different "endpoint" shapes show up in state/output:
  # - module.atlas_aws.privatelink: one AWS interface endpoint per cluster AWS region
  #   (e.g. us-east-1 and us-east-2), each with its own vpc_endpoint_id and security group.
  # - module.atlas_cluster.connection_strings.private_endpoint: Atlas-published client
  #   connection info. For a SHARDED cluster this is typically one MONGOS entry (type
  #   "MONGOS") with a load-balanced SRV hostname (*-pl-0-lb.*), not one row per shard
  #   or per VPC endpoint. endpoints[] lists which customer VPC endpoint(s) that SRV
  #   entry is tied to, keyed by Atlas region (US_EAST_1), not the AWS region substring
  #   in the hostname.
  #
  # Example (multi-region cluster, two privatelink VPC endpoints, one MONGOS SRV):
  #   privatelink["us-east-1"].vpc_endpoint_id = vpce-...ae8
  #   privatelink["us-east-2"].vpc_endpoint_id = vpce-...2d63
  #   private_endpoint[0].srv_connection_string = mongodb+srv://...-pl-0-lb....
  #   private_endpoint[0].endpoints = [{ region = "US_EAST_1", endpoint_id = vpce-...ae8 }]
  #
  # Do not match AWS region names inside the SRV hostname (they are not present); map
  # app aws_region -> Atlas region and look up endpoints[].region. Regions with a VPC
  # endpoint but no matching private_endpoint row fall back to mongo_private_connection_string
  # (same SRV; DNS resolves via the local region's interface endpoint).
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

  app_handoff_payloads = {
    for k, v in local.lambda_apps : k => {
      aws_region                      = v.aws_region
      name_prefix                     = v.name
      private_subnet_ids              = local.app_network[v.aws_region].private_subnet_ids
      lambda_security_group_id        = aws_security_group.lambda[v.aws_region].id
      lambda_execution_role_arn       = aws_iam_role.lambda_exec[k].arn
      mongo_private_connection_string = local.mongo_iam_connection_strings_by_region[v.aws_region]
      app_database_name               = v.primary_database
      ecr_repository_url              = aws_ecr_repository.this[v.ecr_key].repository_url
    }
  }

  ecs_app_handoff_base = {
    for k, v in local.ecs_apps : k => {
      aws_region                      = v.aws_region
      name_prefix                     = v.name
      private_subnet_ids              = local.app_network[v.aws_region].private_subnet_ids
      ecs_security_group_id           = aws_security_group.lambda[v.aws_region].id
      ecs_task_role_arn               = aws_iam_role.ecs_task[k].arn
      ecs_task_execution_role_arn     = aws_iam_role.ecs_task_execution[k].arn
      mongo_private_connection_string = local.mongo_iam_connection_strings_by_region[v.aws_region]
      app_database_name               = v.primary_database
      ecr_repository_url              = aws_ecr_repository.this[v.ecr_key].repository_url
    }
  }

  ecs_app_handoff_http = {
    for k, app in local.ecs_routing_apps : k => {
      alb_arn               = module.http_edge[app.routing.edge].alb_arn
      alb_listener_arn      = module.http_edge[app.routing.edge].listener_arn
      alb_security_group_id = module.http_edge[app.routing.edge].alb_security_group_id
      alb_dns_name          = module.http_edge[app.routing.edge].alb_dns_name
      listener_priority     = app.routing.listener_priority
      path_pattern          = app.routing.path_pattern
      host_header           = coalesce(app.routing.host_header, [])
      container_port        = app.routing.container_port
      health_check_path     = app.routing.health_check_path
    }
  }

  ecs_container_secret_specs = merge([
    for app_key, app in local.ecs_apps : {
      for env_name, spec in app.container_secrets :
      "${app_key}/${env_name}" => {
        app_key     = app_key
        env_name    = env_name
        secret_name = spec.name
        json_key    = spec.json_key
        aws_region  = app.aws_region
      }
    }
  ]...)

  ecs_container_secret_env_vars_by_app = {
    for app_key, app in local.ecs_apps : app_key => merge(
      app.atlas_ai_model_api_key != null ? {
        VOYAGE_API_KEY = module.atlas_ai_model_api_key[app_key].secret_arn
      } : {},
      {
        for env_name, spec in app.container_secrets :
        env_name => (
          spec.json_key != null
          ? "${data.aws_secretsmanager_secret.ecs_container["${app_key}/${env_name}"].arn}:${spec.json_key}::"
          : data.aws_secretsmanager_secret.ecs_container["${app_key}/${env_name}"].arn
        )
      }
    )
  }

  ecs_app_container_env_vars = {
    for k, app in local.ecs_apps : k => merge(
      {
        MONGODB_URI      = local.ecs_app_handoff_base[k].mongo_private_connection_string
        MONGODB_DATABASE = local.ecs_app_handoff_base[k].app_database_name
      },
      app.atlas_ai_model_api_key != null ? {
        VOYAGE_BASE_URL = module.atlas_ai_model_api_key[k].voyage_base_url
      } : {},
      app.container_env_vars
    )
  }

  ecs_apps_with_execution_secrets = {
    for app_key, app in local.ecs_apps : app_key => app
    if app.atlas_ai_model_api_key != null || length(app.container_secrets) > 0
  }

  ecs_execution_secret_arns_by_app = {
    for app_key, app in local.ecs_apps : app_key => distinct(concat(
      app.atlas_ai_model_api_key != null ? [module.atlas_ai_model_api_key[app_key].secret_arn] : [],
      [
        for env_name, spec in app.container_secrets :
        data.aws_secretsmanager_secret.ecs_container["${app_key}/${env_name}"].arn
      ]
    ))
  }

  ecs_app_handoff_payloads = {
    for k, v in local.ecs_app_handoff_base :
    k => merge(v, try(local.ecs_app_handoff_http[k], {}), {
      container_env_vars        = local.ecs_app_container_env_vars[k]
      container_secret_env_vars = local.ecs_container_secret_env_vars_by_app[k]
    })
  }

  ecs_container_ports_by_region = {
    for region in local.ecs_alb_regions : region => distinct([
      for app in local.ecs_routing_apps :
      app.routing.container_port
      if local.http_edges[app.routing.edge].aws_region == region
    ])
  }

  ecs_ingress_from_alb_rules = merge([
    for region, ports in local.ecs_container_ports_by_region : {
      for pair in setproduct(
        ports,
        [for edge_key, edge in local.http_edges : edge_key if edge.aws_region == region]
        ) : "${region}-${pair[0]}-${pair[1]}" => {
        region = region
        port   = pair[0]
        alb_sg = module.http_edge[pair[1]].alb_security_group_id
      }
    }
  ]...)
}

check "mongo_private_connection_string_standard_srv_fallback" {
  assert {
    condition     = !local.mongo_private_connection_string_uses_standard_srv
    error_message = <<-EOT
      mongo_private_connection_string fell back to standard_srv (non-PrivateLink).
      Atlas did not publish private_endpoint or private_srv SRV connection strings yet.
      Lambda apps will receive the public Atlas SRV in MONGO_URL; traffic may not route over PrivateLink,
      and may fail to connect to the cluster if the public internet is unreachable from the app deployment
      and no public IPs are added to the project.
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
      Lambda apps will receive NO_CONNECTION_STRING_AVAILABLE in MONGO_URL and cannot connect until connection strings are published.
    EOT
  }
}

module "vpc" {
  for_each = local.managed_vpc_regions

  source     = "./modules/regional_vpc"
  aws_region = each.key
  name       = "${var.default_resource_name_prefix}-vpc-${each.key}"
  cidr       = local.vpc_cidr_by_region[each.key]
  az_count   = local.vpc_az_count_by_region[each.key]

  enable_nat_gateway    = var.vpc_config.enable_nat_gateway
  create_igw            = var.vpc_config.create_igw
  create_public_subnets = contains(local.ecs_alb_regions, each.key)
  tags                  = var.tags
}

module "http_edge" {
  for_each = local.http_edges

  source              = "./modules/http_edge"
  aws_region          = each.value.aws_region
  name                = "${var.default_resource_name_prefix}-${each.key}"
  security_group_name = "${var.default_resource_name_prefix}-alb-${each.key}"
  vpc_id              = local.app_network[each.value.aws_region].vpc_id
  public_subnet_ids   = local.app_network[each.value.aws_region].public_subnet_ids
  aliases             = each.value.aliases
  acm_certificate_arn = each.value.acm_certificate_arn
  idle_timeout        = each.value.idle_timeout
  tags                = var.tags
}

resource "aws_security_group" "lambda" {
  for_each = local.app_aws_regions

  region      = each.key
  name_prefix = "${var.default_resource_name_prefix}-lambda-"
  description = "Lambda app SG: PrivateLink + VPC endpoint egress only"
  vpc_id      = local.app_network[each.key].vpc_id

  egress {
    description = "Atlas PrivateLink"
    from_port   = 1024
    to_port     = 65535
    protocol    = "tcp"
    cidr_blocks = [local.app_network[each.key].vpc_cidr_block]
  }

  egress {
    description = "VPC interface endpoints HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [local.app_network[each.key].vpc_cidr_block]
  }

  egress {
    description = "VPC DNS"
    from_port   = 53
    to_port     = 53
    protocol    = "udp"
    cidr_blocks = [local.app_network[each.key].vpc_cidr_block]
  }

  egress {
    description     = "S3 via gateway VPC endpoint (ECR layers)"
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    prefix_list_ids = [aws_vpc_endpoint.s3[each.key].prefix_list_id]
  }

  tags = merge(var.tags, { Name = "${var.default_resource_name_prefix}-lambda-${each.key}" })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_security_group" "vpc_endpoints" {
  for_each = local.app_aws_regions

  region      = each.key
  name_prefix = "${var.default_resource_name_prefix}-vpce-"
  description = "Interface VPC endpoints for Lambda AWS API access"
  vpc_id      = local.app_network[each.key].vpc_id

  ingress {
    description     = "HTTPS from Lambda"
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = [aws_security_group.lambda[each.key].id]
  }

  tags = merge(var.tags, { Name = "${var.default_resource_name_prefix}-vpce-${each.key}" })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_endpoint" "interface" {
  for_each = {
    for pair in setproduct(tolist(local.app_aws_regions), ["ecr.api", "ecr.dkr", "logs", "sts"]) :
    "${pair[0]}-${pair[1]}" => {
      region  = pair[0]
      service = pair[1]
    }
  }

  region              = each.value.region
  vpc_id              = local.app_network[each.value.region].vpc_id
  service_name        = "com.amazonaws.${each.value.region}.${each.value.service}"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = local.app_network[each.value.region].private_subnet_ids
  security_group_ids  = [aws_security_group.vpc_endpoints[each.value.region].id]
  private_dns_enabled = true

  tags = merge(var.tags, { Name = "${var.default_resource_name_prefix}-${each.value.region}-${each.value.service}" })
}

resource "aws_vpc_endpoint" "s3" {
  for_each = local.app_aws_regions

  region            = each.key
  vpc_id            = local.app_network[each.key].vpc_id
  service_name      = "com.amazonaws.${each.key}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = local.app_network[each.key].private_route_table_ids

  tags = merge(var.tags, { Name = "${var.default_resource_name_prefix}-s3-${each.key}" })
}

resource "aws_security_group_rule" "ecs_ingress_from_alb" {
  for_each = local.ecs_ingress_from_alb_rules

  region                   = each.value.region
  type                     = "ingress"
  from_port                = each.value.port
  to_port                  = each.value.port
  protocol                 = "tcp"
  security_group_id        = aws_security_group.lambda[each.value.region].id
  source_security_group_id = each.value.alb_sg
  description              = "ECS tasks from HTTP edge ALB"
}

resource "aws_security_group_rule" "atlas_pl_ingress_from_app" {
  for_each = local.app_aws_regions

  region                   = each.key
  type                     = "ingress"
  from_port                = 1024
  to_port                  = 65535
  protocol                 = "tcp"
  security_group_id        = module.atlas_aws.privatelink[each.key].security_group_id
  source_security_group_id = aws_security_group.lambda[each.key].id
  description              = "MongoDB Atlas PrivateLink from app SG"
}

resource "aws_iam_role" "lambda_exec" {
  for_each = local.lambda_apps

  name = "${each.value.name}-lambda-exec"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "lambda_exec" {
  for_each = local.lambda_role_policy_attachments

  role       = aws_iam_role.lambda_exec[each.value.app_key].name
  policy_arn = each.value.policy_arn
}

resource "aws_iam_role" "ecs_task" {
  for_each = local.ecs_apps

  name = "${each.value.name}-ecs-task"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
    }]
  })

  tags = var.tags
}

resource "aws_iam_role" "ecs_task_execution" {
  for_each = local.ecs_apps

  name = "${each.value.name}-ecs-exec"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
    }]
  })

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution" {
  for_each = local.ecs_execution_role_policy_attachments

  role       = aws_iam_role.ecs_task_execution[each.value.app_key].name
  policy_arn = each.value.policy_arn
}

data "aws_secretsmanager_secret" "ecs_container" {
  for_each = local.ecs_container_secret_specs

  region = each.value.aws_region
  name   = each.value.secret_name
}

resource "aws_iam_role_policy" "ecs_task_execution_secrets" {
  for_each = local.ecs_apps_with_execution_secrets

  name = "${each.key}-ecs-exec-secrets"
  role = aws_iam_role.ecs_task_execution[each.key].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["secretsmanager:GetSecretValue"]
      Resource = local.ecs_execution_secret_arns_by_app[each.key]
    }]
  })
}

resource "aws_secretsmanager_secret" "app" {
  for_each = local.lambda_secrets

  region = each.value.aws_region
  name   = each.value.handoff_secret_name
  tags   = var.tags
}

resource "aws_secretsmanager_secret_version" "app" {
  for_each = local.lambda_secrets

  region        = each.value.aws_region
  secret_id     = aws_secretsmanager_secret.app[each.key].id
  secret_string = jsonencode(local.app_handoff_payloads[each.key])
}

resource "local_file" "app_tfvars" {
  for_each = local.lambda_tfvars

  filename = each.value.tfvars_path
  content  = <<-EOT
    aws_region                      = "${local.app_handoff_payloads[each.key].aws_region}"
    name_prefix                     = "${local.app_handoff_payloads[each.key].name_prefix}"
    private_subnet_ids              = ${jsonencode(local.app_handoff_payloads[each.key].private_subnet_ids)}
    lambda_security_group_id        = "${local.app_handoff_payloads[each.key].lambda_security_group_id}"
    lambda_execution_role_arn       = "${local.app_handoff_payloads[each.key].lambda_execution_role_arn}"
    mongo_private_connection_string = "${local.app_handoff_payloads[each.key].mongo_private_connection_string}"
    app_database_name               = "${local.app_handoff_payloads[each.key].app_database_name}"
    ecr_repository_url              = "${local.app_handoff_payloads[each.key].ecr_repository_url}"
  EOT
}

resource "aws_secretsmanager_secret" "ecs_app" {
  for_each = local.ecs_secrets

  region = each.value.aws_region
  name   = each.value.handoff_secret_name
  tags   = var.tags
}

resource "aws_secretsmanager_secret_version" "ecs_app" {
  for_each = local.ecs_secrets

  region        = each.value.aws_region
  secret_id     = aws_secretsmanager_secret.ecs_app[each.key].id
  secret_string = jsonencode(local.ecs_app_handoff_payloads[each.key])
}

resource "local_file" "ecs_app_tfvars" {
  for_each = local.ecs_tfvars

  filename = each.value.tfvars_path
  content = <<-EOT
    aws_region                      = "${local.ecs_app_handoff_payloads[each.key].aws_region}"
    name_prefix                     = "${local.ecs_app_handoff_payloads[each.key].name_prefix}"
    private_subnet_ids              = ${jsonencode(local.ecs_app_handoff_payloads[each.key].private_subnet_ids)}
    ecs_security_group_id           = "${local.ecs_app_handoff_payloads[each.key].ecs_security_group_id}"
    ecs_task_role_arn               = "${local.ecs_app_handoff_payloads[each.key].ecs_task_role_arn}"
    ecs_task_execution_role_arn     = "${local.ecs_app_handoff_payloads[each.key].ecs_task_execution_role_arn}"
    mongo_private_connection_string = "${local.ecs_app_handoff_payloads[each.key].mongo_private_connection_string}"
    app_database_name               = "${local.ecs_app_handoff_payloads[each.key].app_database_name}"
    ecr_repository_url              = "${local.ecs_app_handoff_payloads[each.key].ecr_repository_url}"
    ${contains(keys(local.ecs_app_handoff_http), each.key) ? join("\n", [
  "alb_listener_arn                = \"${local.ecs_app_handoff_payloads[each.key].alb_listener_arn}\"",
  "alb_dns_name                    = \"${local.ecs_app_handoff_payloads[each.key].alb_dns_name}\"",
  "listener_priority               = ${local.ecs_app_handoff_payloads[each.key].listener_priority}",
  "path_pattern                    = ${jsonencode(local.ecs_app_handoff_payloads[each.key].path_pattern)}",
  "container_port                  = ${local.ecs_app_handoff_payloads[each.key].container_port}",
  "health_check_path               = \"${local.ecs_app_handoff_payloads[each.key].health_check_path}\"",
]) : ""}
    container_env_vars              = ${jsonencode(local.ecs_app_handoff_payloads[each.key].container_env_vars)}
    container_secret_env_vars       = ${jsonencode(local.ecs_app_handoff_payloads[each.key].container_secret_env_vars)}
  EOT
}
