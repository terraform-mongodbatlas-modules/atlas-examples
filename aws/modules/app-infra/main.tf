# Shared locals. File-local locals live next to the resources that read them.

locals {
  # --- Regions and app inputs -------------------------------------------------
  regions_resolved = [
    for r in var.regions : {
      aws_name   = replace(lower(r.name), "_", "-")
      node_count = r.node_count
    }
  ]
  aws_region  = local.regions_resolved[0].aws_name
  aws_regions = [for r in local.regions_resolved : r.aws_name]

  ecs_apps = {
    for k, v in var.ecs_apps : k => {
      name                = coalesce(v.name, k)
      ecr_key             = v.ecr_key
      aws_region          = coalesce(v.aws_region, local.aws_region)
      primary_database    = coalesce(v.primary_database, v.roles[0].database_name)
      roles               = v.roles
      runtime_secret_name = "${coalesce(v.name, k)}-app"
      internet_egress     = v.internet_egress
      routing = v.routing != null ? {
        edge              = v.routing.edge
        listener_priority = v.routing.listener_priority
        path_pattern      = v.routing.path_pattern
        host_header       = v.routing.host_header
        container_port    = v.routing.container_port
      } : null
    }
  }
  ecs_routing_apps = {
    for k, v in local.ecs_apps : k => v if v.routing != null
  }

  http_edges = {
    for k, v in var.http_edges : k => {
      aws_region          = coalesce(v.aws_region, local.aws_region)
      aliases             = v.aliases
      acm_certificate_arn = v.acm_certificate_arn
      idle_timeout        = v.idle_timeout
      waf                 = v.waf
    }
  }
  ecs_alb_regions = toset([for edge in local.http_edges : edge.aws_region])

  ecr_repositories = {
    for k, v in var.ecr_repositories : k => {
      name                 = coalesce(v.name, k)
      region               = coalesce(v.region, local.aws_region)
      image_tag_mutability = v.image_tag_mutability
      scan_on_push         = v.scan_on_push
      force_delete         = v.force_delete
      lifecycle_keep_count = v.lifecycle_keep_count
    }
  }
  ecr_lifecycle_policies = {
    for k, v in local.ecr_repositories : k => v.lifecycle_keep_count
    if v.lifecycle_keep_count > 0
  }

  # --- VPC and app network ----------------------------------------------------
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

  # Every cluster region, whether managed here or BYO. Atlas PrivateLink reads
  # this so a cluster region without an app still gets an endpoint.
  region_network = {
    for region in local.aws_regions : region => {
      vpc_id             = var.vpc_config.create ? module.vpc[region].vpc_id : var.vpc_config.by_region[region].vpc_id
      private_subnet_ids = var.vpc_config.create ? module.vpc[region].private_subnets : var.vpc_config.by_region[region].private_subnet_ids
      vpc_cidr_block     = var.vpc_config.create ? module.vpc[region].vpc_cidr_block : var.vpc_config.by_region[region].vpc_cidr_block
    }
  }

  app_aws_regions = setunion(
    toset([for app in local.ecs_apps : app.aws_region]),
    local.ecs_alb_regions
  )
  app_network = {
    for region in local.app_aws_regions : region => {
      vpc_id                  = local.region_network[region].vpc_id
      private_subnet_ids      = local.region_network[region].private_subnet_ids
      vpc_cidr_block          = local.region_network[region].vpc_cidr_block
      private_route_table_ids = var.vpc_config.create ? module.vpc[region].private_route_table_ids : var.vpc_config.by_region[region].private_route_table_ids
    }
  }

  ecs_internet_egress_regions = toset([
    for app in local.ecs_apps : app.aws_region
    if app.internet_egress
  ])
  enable_nat_gateway_by_region = {
    for region in local.managed_vpc_regions :
    region => var.vpc_config.enable_nat_gateway || contains(local.ecs_internet_egress_regions, region)
  }
}
