output "atlas" {
  description = "Atlas project, cluster, connectivity, and module-managed AWS integrations. connection_string_private is hostnames only (PrivateLink); IAM auth supplies credentials at runtime."
  value = {
    project_id                = module.atlas_project.id
    cluster_name              = module.atlas_cluster.cluster_name
    connection_string_private = local.mongo_private_connection_string
    privatelink               = module.atlas_aws.privatelink
    integrations = {
      log_bucket_name    = try(module.atlas_aws.log_integration.bucket_name, null)
      backup_bucket_name = try(module.atlas_aws.backup_export.bucket_name, null)
    }
  }
}

output "network" {
  description = "Primary cluster region VPC (regions[0]). Multi-region VPC layout: operations.vpc_config_resolved."
  value = {
    primary_aws_region = local.aws_region
    vpc_id             = local.vpc_id
    private_subnet_ids = local.private_subnet_ids
    vpc_cidr_block     = local.vpc_cidr_block
  }
}

output "operations" {
  description = "Resolved region and VPC layout for pinning before regions list edits. See docs/lz-changes.md."
  value = {
    regions_resolved = [
      for i, r in local.regions_resolved : {
        index      = i
        aws_region = r.aws_name
        atlas_name = r.atlas_name
        node_count = r.node_count
        primary    = i == 0
      }
    ]
    vpc_config_resolved = var.vpc_config.create ? {
      create             = var.vpc_config.create
      base_cidr          = var.vpc_config.base_cidr
      az_count           = var.vpc_config.az_count
      enable_nat_gateway = var.vpc_config.enable_nat_gateway
      create_igw         = var.vpc_config.create_igw
      by_region = {
        for region in local.aws_regions : region => {
          cidr     = local.vpc_cidr_by_region[region]
          az_count = local.vpc_az_count_by_region[region]
        }
      }
    } : null
  }
}

output "database" {
  description = "Atlas database users and grants from *_apps maps. users is empty when no app targets."
  value = {
    cluster_name = module.atlas_cluster.cluster_name
    users = concat(
      [
        for k, app in local.lambda_apps : {
          id               = k
          source           = "lambda_apps"
          username         = aws_iam_role.lambda_exec[k].arn
          auth_type        = "AWS_IAM_ROLE"
          primary_database = app.primary_database
          grants = [
            for r in app.roles : {
              database_name   = r.database_name
              role_name       = r.role_name
              collection_name = try(r.collection_name, null)
            }
          ]
        }
      ]
    )
  }
}

output "ecr_repositories" {
  description = "ECR registries keyed by ecr_repositories map key."
  value = {
    for k, v in local.ecr_repositories : k => {
      name                 = v.name
      region               = v.region
      repository_url       = aws_ecr_repository.this[k].repository_url
      image_tag_mutability = v.image_tag_mutability
      scan_on_push         = v.scan_on_push
      force_delete         = v.force_delete
      lifecycle_keep_count = v.lifecycle_keep_count
    }
  }
}

output "lambda_apps" {
  description = "Configured Lambda apps and handoff destination. Values for 02_app_* are in infra.auto.tfvars or Secrets Manager."
  value = {
    for k, v in local.lambda_apps : k => {
      name             = v.name
      aws_region       = v.aws_region
      primary_database = v.primary_database
      ecr_key          = v.ecr_key
      tfvars_path      = v.tfvars_path
      secret_name      = v.secret_name
    }
  }
}

output "ecs_apps" {
  description = "Configured ECS apps and handoff destination. Empty until ECS resources land."
  value       = {}
}

output "ec2_apps" {
  description = "Configured EC2 apps and handoff destination. Empty until EC2 resources land."
  value       = {}
}
