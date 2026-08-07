# Common
# ----------------------------------------------------

variable "atlas_org_id" {
  description = "MongoDB Atlas Organization ID"
  type        = string
}

variable "name_prefix" {
  description = "Prefix for project, cluster, VPC, IAM role, and default resource names"
  type        = string
  default     = "fastapi-minimal"
}

variable "tags" {
  description = "Tags applied to Atlas and AWS resources"
  type        = map(string)
  default     = { Example = "aws-fastapi-minimal" }
}

# Cluster
# ----------------------------------------------------

variable "regions" {
  description = "Cluster regions (Arch Center shape). AWS provider region is derived from regions[0].name. PrivateLink uses managed VPC subnets per region (create=true) or vpc_config.by_region (create=false). Lambda apps and ECR repos default to regions[0]; set aws_region / region per entry to place compute and registries in other cluster regions."
  type = list(object({
    name       = string
    node_count = optional(number, 3)
  }))
  default = [{ name = "US_EAST_1", node_count = 3 }]

  validation {
    condition     = length(var.regions) > 0
    error_message = "regions must contain at least one entry."
  }
}

variable "cluster_type" {
  description = "Atlas cluster type. Default SHARDED (production-shaped). Set REPLICASET for cheaper personal labs."
  type        = string
  default     = "SHARDED"

  validation {
    condition     = contains(["SHARDED", "REPLICASET"], var.cluster_type)
    error_message = "cluster_type must be SHARDED or REPLICASET."
  }
}

variable "shard_count" {
  description = "Shard count when cluster_type = SHARDED. Ignored for REPLICASET."
  type        = number
  default     = 2

  validation {
    condition     = var.shard_count >= 1
    error_message = "shard_count must be at least 1."
  }
}

variable "manual_scaling" {
  description = <<-EOT
    Null-gated fixed compute size. Default null keeps Architecture Center compute auto-scaling (M10–M200).
    Set to pin instance_size (disables compute auto-scaling). Disk GB auto-scaling stays enabled either way; this example does not expose disk_size_gb.
  EOT
  type = object({
    instance_size = string
  })
  default  = null
  nullable = true

  validation {
    condition = var.manual_scaling == null || (
      var.manual_scaling.instance_size != "M0" &&
      var.manual_scaling.instance_size != "M2" &&
      var.manual_scaling.instance_size != "M5"
    )
    error_message = "manual_scaling.instance_size must be M10 or higher (M0, M2, and M5 are not allowed)."
  }
}

# Network
# ----------------------------------------------------

variable "vpc_config" {
  description = "App VPC for PrivateLink and Lambda. create=true manages one private VPC per cluster AWS region; create=false requires a full by_region entry per region."
  type = object({
    create             = optional(bool, true)
    base_cidr          = optional(string, "10.0.0.0/8")
    az_count           = optional(number, 2)
    enable_nat_gateway = optional(bool, false)
    create_igw         = optional(bool, false)
    by_region = optional(map(object({
      cidr                    = optional(string)
      az_count                = optional(number)
      vpc_id                  = optional(string)
      private_subnet_ids      = optional(list(string), [])
      vpc_cidr_block          = optional(string)
      private_route_table_ids = optional(list(string), [])
    })), {})
  })
  default = {}

  validation {
    condition     = !var.vpc_config.create || (var.vpc_config.az_count >= 1 && var.vpc_config.az_count <= 6)
    error_message = "vpc_config.az_count must be between 1 and 6 when create = true."
  }

  validation {
    condition = alltrue([
      for key in keys(var.vpc_config.by_region) :
      contains(distinct([for r in var.regions : replace(lower(r.name), "_", "-")]), key)
    ])
    error_message = "vpc_config.by_region keys must match a cluster AWS region from regions."
  }

  validation {
    condition = var.vpc_config.create ? alltrue([
      for _, cfg in var.vpc_config.by_region :
      cfg.vpc_id == null &&
      length(cfg.private_subnet_ids) == 0 &&
      cfg.vpc_cidr_block == null &&
      length(cfg.private_route_table_ids) == 0
    ]) : true
    error_message = "When vpc_config.create = true, by_region may only set cidr and az_count overrides."
  }

  validation {
    condition = !var.vpc_config.create ? alltrue([
      for _, cfg in var.vpc_config.by_region :
      cfg.cidr == null && cfg.az_count == null
    ]) : true
    error_message = "When vpc_config.create = false, by_region may only set BYO VPC fields."
  }

  validation {
    condition = !var.vpc_config.create ? alltrue([
      for region in distinct([for r in var.regions : replace(lower(r.name), "_", "-")]) :
      contains(keys(var.vpc_config.by_region), region) &&
      var.vpc_config.by_region[region].vpc_id != null &&
      length(var.vpc_config.by_region[region].private_subnet_ids) > 0 &&
      var.vpc_config.by_region[region].vpc_cidr_block != null &&
      length(var.vpc_config.by_region[region].private_route_table_ids) > 0
    ]) : true
    error_message = "When vpc_config.create = false, set vpc_id, private_subnet_ids, vpc_cidr_block, and private_route_table_ids in by_region for every cluster AWS region."
  }

  validation {
    condition = var.vpc_config.create ? (
      length(distinct([
        for i, region in sort(distinct([for r in var.regions : replace(lower(r.name), "_", "-")])) :
        coalesce(try(var.vpc_config.by_region[region].cidr, null), cidrsubnet(var.vpc_config.base_cidr, 8, i))
      ])) == length(distinct([for r in var.regions : replace(lower(r.name), "_", "-")]))
    ) : true
    error_message = "Managed VPC CIDRs must be unique per cluster AWS region."
  }

  validation {
    condition     = !var.vpc_config.create || length(distinct([for r in var.regions : replace(lower(r.name), "_", "-")])) <= 256
    error_message = "Too many cluster AWS regions for vpc_config.base_cidr (max 256 /16 blocks from a /8 base)."
  }
}

# Atlas AWS integrations (CPA / encryption / log / backup)
# ----------------------------------------------------

variable "s3_force_destroy" {
  description = "Force-destroy module-managed log and backup export S3 buckets even when non-empty. Enable for ephemeral demos; disable for shared accounts that must retain objects."
  type        = bool
  default     = true
}

# Container registries
# ----------------------------------------------------

variable "ecr_repositories" {
  description = <<-EOT
    ECR repositories managed by 01_lz. Independent of lambda_apps / ecs_apps so registries survive compute changes (for example Lambda to ECS).
    Map keys are stable identities. Each entry creates a repository; lifecycle_keep_count > 0 adds a lifecycle policy (keep last N images).
    force_delete defaults true for demo tear-down (set false to block destroy while images remain).
    image_tag_mutability defaults to IMMUTABLE (retagging the same tag fails; bump image_tag on each push). Use MUTABLE only if you intentionally overwrite tags.
  EOT
  type = map(object({
    name                 = optional(string)
    region               = optional(string)
    image_tag_mutability = optional(string, "IMMUTABLE")
    scan_on_push         = optional(bool, true)
    force_delete         = optional(bool, true)
    lifecycle_keep_count = optional(number, 10)
  }))
  default = {
    default = {}
  }

  validation {
    condition = alltrue([
      for _, repo in var.ecr_repositories :
      contains(["MUTABLE", "IMMUTABLE"], repo.image_tag_mutability)
    ])
    error_message = "ecr_repositories.*.image_tag_mutability must be MUTABLE or IMMUTABLE."
  }

  validation {
    condition = alltrue([
      for _, repo in var.ecr_repositories :
      repo.lifecycle_keep_count >= 0
    ])
    error_message = "ecr_repositories.*.lifecycle_keep_count must be >= 0 (0 disables the lifecycle policy)."
  }

  validation {
    condition = alltrue([
      for _, repo in var.ecr_repositories :
      contains(
        distinct([for r in var.regions : replace(lower(r.name), "_", "-")]),
        coalesce(repo.region, replace(lower(var.regions[0].name), "_", "-"))
      )
    ])
    error_message = "ecr_repositories.*.region must be a cluster AWS region from regions."
  }
}

# Apps
# ----------------------------------------------------

variable "lambda_apps" {
  description = <<-EOT
    Lambda apps to provision. Map keys are stable identities.
    Each entry creates one IAM execution role and one Atlas IAM database user (username = that role ARN).
    ecr_key selects an entry in ecr_repositories (registry lifecycle is not tied to this map).
    roles maps to mongodbatlas_database_user.roles (multi-database / multi-role). role_name defaults to readWrite.
    primary_database is the DB_NAME for the app stack; defaults to roles[0].database_name.
    tfvars_path: relative path for a per-app infra.auto.tfvars writer; null/omit disables the file for that app.
    secret: null-gated Secrets Manager handoff for that app ({ name = optional } ; name defaults to <app-name>-app).
    Auth is IAM ROLE only in this example (no password, OIDC, or X.509).
  EOT
  type = map(object({
    name             = optional(string)
    ecr_key          = string
    aws_region       = optional(string)
    primary_database = optional(string)
    tfvars_path      = optional(string)
    secret = optional(object({
      name = optional(string)
    }))
    roles = list(object({
      role_name       = optional(string, "readWrite")
      database_name   = string
      collection_name = optional(string)
    }))
  }))
  default = {
    default = {
      ecr_key     = "default"
      roles       = [{ database_name = "test" }]
      tfvars_path = "../02_app_lambda/infra.auto.tfvars"
    }
  }

  validation {
    condition     = length(var.lambda_apps) > 0
    error_message = "lambda_apps must contain at least one entry."
  }

  validation {
    condition     = alltrue([for _, app in var.lambda_apps : length(app.roles) > 0])
    error_message = "Each lambda_apps entry must include at least one roles entry."
  }

  validation {
    condition = alltrue([
      for _, app in var.lambda_apps :
      contains(keys(var.ecr_repositories), app.ecr_key)
    ])
    error_message = "Each lambda_apps.*.ecr_key must exist in ecr_repositories."
  }

  validation {
    condition = length(distinct([
      for _, app in var.lambda_apps : app.tfvars_path
      if app.tfvars_path != null && app.tfvars_path != ""
      ])) == length([
      for _, app in var.lambda_apps : app.tfvars_path
      if app.tfvars_path != null && app.tfvars_path != ""
    ])
    error_message = "lambda_apps.*.tfvars_path values must be unique when set."
  }

  validation {
    condition = alltrue([
      for _, app in var.lambda_apps :
      contains(
        distinct([for r in var.regions : replace(lower(r.name), "_", "-")]),
        coalesce(app.aws_region, replace(lower(var.regions[0].name), "_", "-"))
      )
    ])
    error_message = "lambda_apps.*.aws_region must be a cluster AWS region from regions."
  }

  validation {
    condition = alltrue([
      for _, app in var.lambda_apps :
      coalesce(app.aws_region, replace(lower(var.regions[0].name), "_", "-")) ==
      coalesce(
        try(var.ecr_repositories[app.ecr_key].region, null),
        replace(lower(var.regions[0].name), "_", "-")
      )
    ])
    error_message = "lambda_apps.*.aws_region must match ecr_repositories[ecr_key].region (after defaults)."
  }
}

variable "ecs_apps" {
  description = "Reserved for future ECS apps (same shape as lambda_apps, including tfvars_path and secret). No resources are created from this map yet."
  type = map(object({
    name             = optional(string)
    ecr_key          = string
    aws_region       = optional(string)
    primary_database = optional(string)
    tfvars_path      = optional(string)
    secret = optional(object({
      name = optional(string)
    }))
    roles = list(object({
      role_name       = optional(string, "readWrite")
      database_name   = string
      collection_name = optional(string)
    }))
  }))
  default = {}

  validation {
    condition = alltrue([
      for _, app in var.ecs_apps :
      contains(
        distinct([for r in var.regions : replace(lower(r.name), "_", "-")]),
        coalesce(app.aws_region, replace(lower(var.regions[0].name), "_", "-"))
      )
    ])
    error_message = "ecs_apps.*.aws_region must be a cluster AWS region from regions."
  }
}
