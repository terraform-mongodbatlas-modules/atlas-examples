# Atlas: project, AWS integration (PrivateLink, KMS, log/backup), and cluster.
# These are the published modules, composed here so the wiring is readable.

locals {
  atlas_region_names = distinct([for r in local.regions_resolved : r.atlas_name])
  cluster_regions = [
    for r in local.regions_resolved : {
      name       = r.atlas_name
      node_count = r.node_count
    }
  ]
  cluster_instance_size = try(var.manual_scaling.instance_size, null)
  cluster_auto_scaling = {
    compute_enabled           = var.manual_scaling == null
    compute_min_instance_size = var.auto_scaling_min_instance_size
    disk_gb_enabled           = true
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
  source = "terraform-mongodbatlas-modules/atlas-aws/mongodbatlas"

  project_id = module.atlas_project.id

  # PrivateLink into the app infra VPC. module.app_infra must come first:
  # these are its subnet IDs.
  privatelink_endpoints = [
    for r in local.regions_resolved : {
      region     = r.atlas_name
      subnet_ids = module.app_infra.region_network[r.aws_name].private_subnet_ids
      security_group = {
        inbound_cidr_blocks = [module.app_infra.region_network[r.aws_name].vpc_cidr_block]
      }
    }
  ]

  encryption      = local.atlas_aws_encryption
  log_integration = local.atlas_aws_log_integration
  backup_export   = local.atlas_aws_backup_export

  aws_tags = var.tags

  # No explicit depends_on here. project_id already orders create after the Atlas
  # project exists. depends_on = [module.atlas_project] defers every data source
  # read inside atlas_aws (including PrivateLink vpc_id) whenever the project
  # module has pending changes (e.g. public_debug_access ip_access_list), which
  # forces unnecessary PrivateLink destroy/recreate. See hashicorp/terraform#26383.
}

module "atlas_cluster" {
  source  = "terraform-mongodbatlas-modules/cluster/mongodbatlas"
  version = "~> 0.4"

  project_id    = module.atlas_project.id
  name          = var.cluster_name
  provider_name = "AWS"
  cluster_type  = var.cluster_type
  shard_count   = var.cluster_type == "SHARDED" ? var.shard_count : null

  regions                     = local.cluster_regions
  instance_size               = local.cluster_instance_size
  auto_scaling                = local.cluster_auto_scaling
  version_release_system      = "CONTINUOUS"
  encryption_at_rest_provider = module.atlas_aws.encryption_at_rest_provider
  tags                        = var.tags

  depends_on = [module.atlas_aws] # force wait on the privatelink
}

# --- Database users -----------------------------------------------------------

# One IAM database user per ECS app. Username is the task role ARN, so the
# container authenticates with MONGODB-AWS and no password.
resource "mongodbatlas_database_user" "ecs" {
  for_each = local.ecs_apps

  project_id         = module.atlas_project.id
  username           = module.app_infra.aws.ecs_task_roles[each.key]
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

# Optional SCRAM user for laptop debugging (public_debug_access).
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

# --- PrivateLink wiring -------------------------------------------------------

# Atlas PrivateLink endpoint SG accepts 1024-65535 from the app SG. The endpoint
# and the app SG are created by different modules, so the rule lives here.
resource "aws_security_group_rule" "atlas_pl_ingress_from_app" {
  for_each = local.app_aws_regions

  region                   = each.key
  type                     = "ingress"
  from_port                = 1024
  to_port                  = 65535
  protocol                 = "tcp"
  security_group_id        = module.atlas_aws.privatelink[each.key].security_group_id
  source_security_group_id = module.app_infra.aws.compute[each.key].app_security_group_id
  description              = "MongoDB Atlas PrivateLink from app SG"
}
