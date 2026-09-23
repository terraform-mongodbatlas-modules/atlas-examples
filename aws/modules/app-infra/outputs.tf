output "aws" {
  description = "AWS resource IDs grouped by landing-zone feature. Atlas IDs, bucket names, and connection strings are caller-owned (built from the atlas-aws and cluster modules)."
  value = {
    cloud_provider_access_role_arn = null

    vpcs = var.vpc_config.create ? {
      for region in local.aws_regions : region => {
        vpc_id              = module.vpc[region].vpc_id
        private_subnet_ids  = module.vpc[region].private_subnets
        public_subnet_ids   = module.vpc[region].public_subnets
        nat_gateway_enabled = local.enable_nat_gateway_by_region[region]
        vpc_cidr_block      = module.vpc[region].vpc_cidr_block
      }
      } : {
      for region, cfg in var.vpc_config.by_region : region => {
        vpc_id              = cfg.vpc_id
        private_subnet_ids  = cfg.private_subnet_ids
        public_subnet_ids   = cfg.public_subnet_ids
        nat_gateway_enabled = false
        vpc_cidr_block      = cfg.vpc_cidr_block
      }
    }

    compute = {
      for region in local.app_aws_regions : region => {
        app_security_group_id = aws_security_group.app[region].id
      }
    }

    http_edges = {
      for k, v in local.http_edges : k => {
        aws_region          = v.aws_region
        https_url           = module.http_edge[k].https_url
        cloudfront_domain   = module.http_edge[k].cloudfront_domain_name
        cloudfront_id       = module.http_edge[k].cloudfront_distribution_id
        vpc_origin_id       = module.http_edge[k].vpc_origin_id
        alb_dns_name        = module.http_edge[k].alb_dns_name
        alb_arn             = module.http_edge[k].alb_arn
        listener_arn        = module.http_edge[k].listener_arn
        aliases             = v.aliases
        acm_certificate_arn = v.acm_certificate_arn
      }
    }

    ecs_task_roles = {
      for k in keys(local.ecs_apps) : k => aws_iam_role.ecs_task[k].arn
    }

    ecs_task_role_names = {
      for k in keys(local.ecs_apps) : k => aws_iam_role.ecs_task[k].name
    }

    ecs_task_execution_roles = {
      for k in keys(local.ecs_apps) : k => aws_iam_role.ecs_task_execution[k].arn
    }
  }
}

output "region_network" {
  description = "Per-cluster-AWS-region VPC IDs, private subnets, and CIDR blocks for every region in regions. Atlas PrivateLink endpoints and the app-to-Atlas SG rule read this."
  value = {
    for region in local.aws_regions : region => {
      vpc_id             = local.region_network[region].vpc_id
      private_subnet_ids = local.region_network[region].private_subnet_ids
      vpc_cidr_block     = local.region_network[region].vpc_cidr_block
    }
  }
}

output "operations" {
  description = "Cluster region layout and VPC pinning. Copy vpc_pin into vpc_config.by_region before reordering regions (managed VPC only). VPC IDs: aws.vpcs."
  value = {
    regions = [
      for r in local.regions_resolved : {
        aws_region = r.aws_name
        node_count = r.node_count
      }
    ]

    vpc_pin = var.vpc_config.create ? {
      for region in local.aws_regions : region => {
        cidr     = local.vpc_cidr_by_region[region]
        az_count = local.vpc_az_count_by_region[region]
      }
    } : null
  }
}

output "ecr_repositories" {
  description = "ECR repository URLs keyed by ecr_repositories map key."
  value = {
    for k in keys(local.ecr_repositories) : k => aws_ecr_repository.this[k].repository_url
  }
}

output "ecs_apps" {
  description = "Resolved ECS apps for the example to store and pass to ecs-service. The caller owns the database name and connection string."
  value = {
    for k, v in local.ecs_apps : k => {
      name                = v.name
      aws_region          = v.aws_region
      ecr_repository_url  = aws_ecr_repository.this[v.ecr_key].repository_url
      runtime_secret_name = v.runtime_secret_name
      network = {
        private_subnet_ids    = local.app_network[v.aws_region].private_subnet_ids
        ecs_security_group_id = aws_security_group.app[v.aws_region].id
      }
      iam = {
        task_role_arn           = aws_iam_role.ecs_task[k].arn
        task_execution_role_arn = aws_iam_role.ecs_task_execution[k].arn
      }
      routing = v.routing == null ? null : {
        edge              = v.routing.edge
        listener_arn      = module.http_edge[v.routing.edge].listener_arn
        listener_priority = v.routing.listener_priority
        path_pattern      = coalesce(v.routing.path_pattern, [])
        host_header       = coalesce(v.routing.host_header, [])
        container_port    = v.routing.container_port
      }
    }
  }
}
