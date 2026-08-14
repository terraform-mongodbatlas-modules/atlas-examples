output "connection_string_public" {
  description = "Full mongodb+srv:// URI with SCRAM credentials when public_debug_access is set. Null when disabled."
  value       = var.public_debug_access != null ? local.public_debug_connection_string : null
  sensitive   = true
}

output "atlas" {
  description = "Atlas project, cluster, connectivity, and module-managed integrations. connection_string_private is hostname-only PrivateLink SRV (diagnostic); ecs_apps.mongo.connection_string appends IAM auth query params."
  value = {
    project_id                = module.atlas_project.id
    cluster_name              = module.atlas_cluster.cluster_name
    connection_string_private = local.mongo_private_connection_string
    privatelink = {
      for k, pl in module.atlas_aws.privatelink : k => {
        vpc_endpoint_id   = pl.vpc_endpoint_id
        security_group_id = pl.security_group_id
        status            = pl.status
      }
    }
    log_bucket_name               = try(module.atlas_aws.log_integration.bucket_name, null)
    log_integration_ids           = try(module.atlas_aws.log_integration.integration_ids, null)
    backup_bucket_name            = try(module.atlas_aws.backup_export.bucket_name, null)
    backup_export_bucket_id       = try(module.atlas_aws.backup_export.export_bucket_id, null)
    cloud_provider_access_role_id = module.atlas_aws.role_id
  }
}

output "aws" {
  description = "AWS resource IDs grouped by landing-zone feature. Atlas IDs and bucket names: atlas output."
  value = {
    cloud_provider_access_role_arn = try(module.atlas_aws.resource_ids.iam_role_arn, null)

    encryption = module.atlas_aws.encryption == null ? null : {
      kms_key_arn = module.atlas_aws.encryption.kms_key_arn
      valid       = module.atlas_aws.encryption.valid
      private_endpoint_status = {
        for region, ep in module.atlas_aws.encryption.private_endpoints : region => ep.status
      }
    }

    log_integration = module.atlas_aws.log_integration == null ? null : {
      bucket_arn = module.atlas_aws.log_integration.bucket_arn
    }

    backup_export = module.atlas_aws.backup_export == null ? null : {
      bucket_arn = module.atlas_aws.backup_export.bucket_arn
    }

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

    ecs_task_execution_roles = {
      for k in keys(local.ecs_apps) : k => aws_iam_role.ecs_task_execution[k].arn
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

output "database_users" {
  description = "Atlas database users and grants from ecs_apps. Empty list when no app targets."
  value = concat(
    [
      for k, app in local.ecs_apps : {
        id               = k
        compute          = "ecs"
        username         = aws_iam_role.ecs_task[k].arn
        primary_database = app.primary_database
        grants = [
          for r in app.roles : {
            database_name   = r.database_name
            role_name       = r.role_name
            collection_name = try(r.collection_name, null)
          }
        ]
      }
    ],
    var.public_debug_access != null ? [
      {
        id               = "public_debug"
        compute          = null
        username         = var.public_debug_access.username
        primary_database = var.public_debug_access.database_name
        grants = [{
          database_name   = var.public_debug_access.database_name
          role_name       = var.public_debug_access.role_name
          collection_name = null
        }]
      }
    ] : []
  )
}

output "ecr_repositories" {
  description = "ECR repository URLs keyed by ecr_repositories map key."
  value = {
    for k in keys(local.ecr_repositories) : k => aws_ecr_repository.this[k].repository_url
  }
}

output "ecs_apps" {
  description = "Resolved ECS apps for the example to store and pass to ecs-service. Origin header values: http_edge_origin_header_values."
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
      mongo = {
        connection_string = local.mongo_iam_connection_strings_by_region[v.aws_region]
        database_name     = v.primary_database
      }
      routing = v.routing == null ? null : {
        edge               = v.routing.edge
        listener_arn       = module.http_edge[v.routing.edge].listener_arn
        listener_priority  = v.routing.listener_priority
        path_pattern       = coalesce(v.routing.path_pattern, [])
        host_header        = coalesce(v.routing.host_header, [])
        container_port     = v.routing.container_port
        origin_header_name = module.http_edge[v.routing.edge].origin_header_name
      }
    }
  }
}

output "http_edge_origin_header_values" {
  description = "CloudFront origin-verify header values keyed by http_edges map key."
  sensitive   = true
  value       = { for k, v in local.http_edges : k => module.http_edge[k].origin_header_value }
}
