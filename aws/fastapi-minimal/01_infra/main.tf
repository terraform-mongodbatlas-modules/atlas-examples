module "atlas_project" {
  source  = "terraform-mongodbatlas-modules/project/mongodbatlas"
  version = "~> 0.2"

  org_id         = var.atlas_org_id
  name           = var.name_prefix
  tags           = var.tags
  ip_access_list = []
}

module "atlas_aws" {
  source  = "terraform-mongodbatlas-modules/atlas-aws/mongodbatlas"
  version = "~> 0.3"

  project_id = module.atlas_project.id

  # CPA: omit cloud_provider_access (module default create = true).
  # To BYO: cloud_provider_access = { create = false, existing = { role_id = "...", iam_role_arn = "..." } }

  privatelink_endpoints = [
    {
      region     = var.atlas_region
      subnet_ids = module.vpc.private_subnets
    }
  ]

  # Disable: encryption = { enabled = false }
  encryption = {
    enabled = true
    create_kms_key = {
      enabled = true
      # For non-ephemeral accounts, raise deletion_window_in_days (max 30).
    }
    private_endpoint_regions = [local.aws_region]
  }

  # Disable: log_integration = { enabled = false }
  log_integration = {
    enabled = true
    create_s3_bucket = {
      enabled       = true
      force_destroy = var.s3_force_destroy
      name_prefix   = "${var.name_prefix}-logs-"
    }
    integrations = [
      { log_types = ["MONGOD"], prefix_path = "operational" },
      { log_types = ["MONGOD_AUDIT"], prefix_path = "audit" },
    ]
  }

  # Disable: backup_export = { enabled = false }
  backup_export = {
    enabled = true
    create_s3_bucket = {
      enabled       = true
      force_destroy = var.s3_force_destroy
      name_prefix   = "${var.name_prefix}-backup-"
    }
  }

  aws_tags = var.tags

  depends_on = [module.atlas_project]
}

module "atlas_cluster" {
  source  = "terraform-mongodbatlas-modules/cluster/mongodbatlas"
  version = "~> 0.4"

  project_id    = module.atlas_project.id
  name          = var.name_prefix
  provider_name = "AWS"
  cluster_type  = "REPLICASET"

  regions = [
    {
      name       = var.atlas_region
      node_count = 3
    }
  ]

  # Leave auto_scaling / backup_enabled / retain_backups_enabled at module defaults
  # (compute autoscaling on, min M10, max M200, backups retained). Pin sizes via auto_scaling if needed.

  encryption_at_rest_provider = module.atlas_aws.encryption_at_rest_provider
  tags                        = var.tags

  depends_on = [module.atlas_aws]
}

/*
  IAM DB user for the Lambda execution role.
  Privilege: readWrite on `test` only (enough to create DB/collection + CRUD).
  t16-02: do not use admin.command("ping"); ping the app DB or rely on find/upsert.
*/
resource "mongodbatlas_database_user" "lambda" {
  project_id         = module.atlas_project.id
  username           = aws_iam_role.lambda_exec.arn
  auth_database_name = "$external"
  aws_iam_type       = "ROLE"

  roles {
    role_name     = "readWrite"
    database_name = "test"
  }

  depends_on = [module.atlas_cluster]
}
