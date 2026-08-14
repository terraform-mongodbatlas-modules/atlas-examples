data "aws_caller_identity" "current" {}

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

  app_aws_regions = setunion(
    toset([for app in local.ecs_apps : app.aws_region]),
    local.ecs_alb_regions
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

  ecs_container_ports_by_region = {
    for region in local.ecs_alb_regions : region => distinct([
      for app in local.ecs_routing_apps :
      app.routing.container_port
      if local.http_edges[app.routing.edge].aws_region == region
    ])
  }

  ecs_internet_egress_regions = toset([
    for app in local.ecs_apps : app.aws_region
    if app.internet_egress
  ])
  enable_nat_gateway_by_region = {
    for region in local.managed_vpc_regions :
    region => var.vpc_config.enable_nat_gateway || contains(local.ecs_internet_egress_regions, region)
  }
  app_regions_with_internet_egress = toset(concat(
    var.vpc_config.enable_nat_gateway ? tolist(local.app_aws_regions) : [],
    tolist(local.ecs_internet_egress_regions)
  ))
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

module "vpc" {
  for_each = local.managed_vpc_regions

  source     = "./modules/regional_vpc"
  aws_region = each.key
  name       = "${var.default_resource_name_prefix}-vpc-${each.key}"
  cidr       = local.vpc_cidr_by_region[each.key]
  az_count   = local.vpc_az_count_by_region[each.key]

  enable_nat_gateway    = local.enable_nat_gateway_by_region[each.key]
  single_nat_gateway    = var.vpc_config.single_nat_gateway
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
  waf                 = each.value.waf
  tags                = var.tags
}

resource "aws_security_group" "app" {
  for_each = local.app_aws_regions

  region      = each.key
  name_prefix = "${var.default_resource_name_prefix}-app-"
  description = "App SG: PrivateLink + VPC endpoint egress"
  vpc_id      = local.app_network[each.key].vpc_id

  dynamic "ingress" {
    for_each = merge([
      for edge_key, edge in local.http_edges : {
        for port in lookup(local.ecs_container_ports_by_region, each.key, []) :
        "${edge_key}-${port}" => {
          port   = port
          alb_sg = module.http_edge[edge_key].alb_security_group_id
        }
        if edge.aws_region == each.key
      }
    ]...)
    content {
      description     = "ECS tasks from HTTP edge ALB"
      from_port       = ingress.value.port
      to_port         = ingress.value.port
      protocol        = "tcp"
      security_groups = [ingress.value.alb_sg]
    }
  }

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

  dynamic "egress" {
    for_each = contains(local.app_regions_with_internet_egress, each.key) ? [1] : []
    content {
      description = "Internet HTTPS via NAT (ecs_apps internet_egress or vpc_config.enable_nat_gateway)"
      from_port   = 443
      to_port     = 443
      protocol    = "tcp"
      cidr_blocks = ["0.0.0.0/0"]
    }
  }

  tags = merge(var.tags, { Name = "${var.default_resource_name_prefix}-app-${each.key}" })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_security_group" "vpc_endpoints" {
  for_each = local.app_aws_regions

  region      = each.key
  name_prefix = "${var.default_resource_name_prefix}-vpce-"
  description = "Interface VPC endpoints for ECS AWS API access"
  vpc_id      = local.app_network[each.key].vpc_id

  ingress {
    description     = "HTTPS from app"
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = [aws_security_group.app[each.key].id]
  }

  tags = merge(var.tags, { Name = "${var.default_resource_name_prefix}-vpce-${each.key}" })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_endpoint" "interface" {
  for_each = {
    for pair in setproduct(tolist(local.app_aws_regions), ["ecr.api", "ecr.dkr", "logs", "secretsmanager", "sts"]) :
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

resource "aws_security_group_rule" "atlas_pl_ingress_from_app" {
  for_each = local.app_aws_regions

  region                   = each.key
  type                     = "ingress"
  from_port                = 1024
  to_port                  = 65535
  protocol                 = "tcp"
  security_group_id        = module.atlas_aws.privatelink[each.key].security_group_id
  source_security_group_id = aws_security_group.app[each.key].id
  description              = "MongoDB Atlas PrivateLink from app SG"
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

resource "aws_iam_role_policy" "ecs_task_execution_handoff" {
  for_each = local.ecs_apps

  name = "${each.key}-ecs-exec-handoff"
  role = aws_iam_role.ecs_task_execution[each.key].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["secretsmanager:GetSecretValue"]
      Resource = "arn:aws:secretsmanager:${each.value.aws_region}:${data.aws_caller_identity.current.account_id}:secret:${each.value.handoff_secret_name}-*"
    }]
  })
}
