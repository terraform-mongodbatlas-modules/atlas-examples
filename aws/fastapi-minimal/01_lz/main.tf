locals {
  regions_resolved = [
    for r in var.regions : {
      aws_name   = replace(lower(r.name), "_", "-")
      atlas_name = upper(replace(replace(lower(r.name), "_", "-"), "-", "_"))
      node_count = r.node_count
    }
  ]
  aws_region         = local.regions_resolved[0].aws_name
  aws_regions        = [for r in local.regions_resolved : r.aws_name]
  atlas_region_names = distinct([for r in local.regions_resolved : r.atlas_name])
  cluster_regions = [
    for r in local.regions_resolved : {
      name       = r.atlas_name
      node_count = r.node_count
    }
  ]

  lambda_apps = {
    for k, v in var.lambda_apps : k => {
      name             = coalesce(v.name, k)
      ecr_key          = v.ecr_key
      aws_region       = coalesce(v.aws_region, local.aws_region)
      primary_database = coalesce(v.primary_database, v.roles[0].database_name)
      roles            = v.roles
      tfvars_path      = v.tfvars_path != null && v.tfvars_path != "" ? v.tfvars_path : null
      secret_name = (
        v.secret == null
        ? null
        : coalesce(v.secret.name, "${coalesce(v.name, k)}-app")
      )
    }
  }
  lambda_tfvars  = { for k, v in local.lambda_apps : k => v if v.tfvars_path != null }
  lambda_secrets = { for k, v in local.lambda_apps : k => v if v.secret_name != null }

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

  # Disk GB auto-scaling is always on. Compute auto-scales unless manual_scaling is set.
  cluster_instance_size = try(var.manual_scaling.instance_size, null)
  cluster_auto_scaling = {
    compute_enabled = var.manual_scaling == null
    disk_gb_enabled = true
  }

  lambda_managed_policies = {
    basic = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
    vpc   = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
    ecr   = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
    xray  = "arn:aws:iam::aws:policy/AWSXRayDaemonWriteAccess"
  }
  lambda_role_policy_attachments = {
    for pair in setproduct(keys(local.lambda_apps), keys(local.lambda_managed_policies)) :
    "${pair[0]}-${pair[1]}" => {
      app_key    = pair[0]
      policy_arn = local.lambda_managed_policies[pair[1]]
    }
  }

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
    create_kms_key = (
      var.atlas_integrations.encryption.enabled && var.atlas_integrations.encryption.kms_key_arn == null
      ? {
        enabled                 = true
        deletion_window_in_days = var.atlas_integrations.encryption.create_kms_key.deletion_window_in_days
        enable_key_rotation     = var.atlas_integrations.encryption.create_kms_key.enable_key_rotation
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
}

module "atlas_project" {
  source  = "terraform-mongodbatlas-modules/project/mongodbatlas"
  version = "~> 0.2"

  org_id = var.atlas_org_id
  name   = var.default_resource_name_prefix
  tags   = var.tags
  ip_access_list = var.public_debug_access != null ? [
    {
      source  = var.public_debug_access.ip_address
      comment = var.public_debug_access.comment
    }
  ] : []
}

module "atlas_aws" {
  # Temporary: use the upstream main branch until the AWS provider 6 deprecation fix is released.
  source = "git::https://github.com/terraform-mongodbatlas-modules/terraform-mongodbatlas-atlas-aws.git?ref=main"

  project_id = module.atlas_project.id

  privatelink_endpoints = [
    for r in local.regions_resolved : {
      region     = r.atlas_name
      subnet_ids = local.privatelink_subnet_ids_by_region[r.aws_name]
    }
  ]

  encryption      = local.atlas_aws_encryption
  log_integration = local.atlas_aws_log_integration
  backup_export   = local.atlas_aws_backup_export

  aws_tags = var.tags

  depends_on = [module.atlas_project]
}

module "atlas_cluster" {
  source  = "terraform-mongodbatlas-modules/cluster/mongodbatlas"
  version = "~> 0.4"

  project_id    = module.atlas_project.id
  name          = var.cluster_name
  provider_name = "AWS"
  cluster_type  = var.cluster_type
  shard_count   = var.cluster_type == "SHARDED" ? var.shard_count : null

  regions       = local.cluster_regions
  instance_size = local.cluster_instance_size
  auto_scaling  = local.cluster_auto_scaling

  encryption_at_rest_provider = module.atlas_aws.encryption_at_rest_provider
  tags                        = var.tags

  depends_on = [module.atlas_aws]
}

resource "mongodbatlas_database_user" "lambda" {
  for_each = local.lambda_apps

  project_id         = module.atlas_project.id
  username           = aws_iam_role.lambda_exec[each.key].arn
  auth_database_name = "$external"
  aws_iam_type       = "ROLE"

  dynamic "roles" {
    for_each = each.value.roles

    content {
      role_name       = roles.value.role_name
      database_name   = roles.value.database_name
      collection_name = roles.value.collection_name
    }
  }

  depends_on = [module.atlas_cluster]
}

resource "random_password" "public_debug" {
  count   = var.public_debug_access != null && try(var.public_debug_access.password, null) == null ? 1 : 0
  length  = 24
  special = false
}

resource "mongodbatlas_database_user" "public_debug" {
  count = var.public_debug_access != null ? 1 : 0

  project_id         = module.atlas_project.id
  username           = var.public_debug_access.username
  password           = local.public_debug_password
  auth_database_name = "admin"

  roles {
    role_name     = var.public_debug_access.role_name
    database_name = var.public_debug_access.database_name
  }

  depends_on = [module.atlas_cluster]
}
