# Common
# ----------------------------------------------------

variable "atlas_org_id" {
  description = "MongoDB Atlas Organization ID"
  type        = string
}

variable "cluster_name" {
  description = "Atlas cluster name."
  type        = string

  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9-]{0,62}[a-zA-Z0-9]$", var.cluster_name))
    error_message = "cluster_name must be 2–64 characters, start with a letter, and contain only letters, digits, and hyphens."
  }
}

variable "default_resource_name_prefix" {
  description = "Prefix for Atlas project name and AWS resource names (VPC, security groups, module-managed S3 buckets)."
  type        = string
  default     = "fastapi-minimal"
}

variable "public_debug_access" {
  description = <<-EOT
    Opt-in public internet access for debugging (SCRAM + IP allowlist).
    Default null disables this path. Use only for short-lived debugging; production apps should use PrivateLink + IAM auth.
    Default grant is readWrite on database test. For read/write on all databases, set role_name = "readWriteAnyDatabase" and database_name = "admin".
  EOT
  type = object({
    ip_address    = string
    username      = optional(string, "debug")
    password      = optional(string)
    database_name = optional(string, "test")
    role_name     = optional(string, "readWrite")
    comment       = optional(string, "public debug")
  })
  default  = null
  nullable = true

  validation {
    condition = var.public_debug_access == null || (
      !strcontains(var.public_debug_access.ip_address, ":") &&
      length(split(".", var.public_debug_access.ip_address)) == 4 &&
      can(cidrhost("${var.public_debug_access.ip_address}/32", 0))
    )
    error_message = "public_debug_access.ip_address must be a single IPv4 address (e.g. 1.2.3.4)."
  }
}

variable "tags" {
  description = "Tags applied to Atlas and AWS resources"
  type        = map(string)
  default     = { Example = "aws-fastapi-minimal" }
}

# Cluster
# ----------------------------------------------------

variable "regions" {
  description = "Cluster regions. Use AWS region names (e.g. us-east-1). Atlas format (US_EAST_1) is also accepted."
  type = list(object({
    name       = string
    node_count = optional(number, 3)
  }))
  default = [{ name = "us-east-1", node_count = 3 }]

  validation {
    condition     = length(var.regions) > 0
    error_message = "regions must contain at least one entry."
  }

  validation {
    condition = length(distinct([
      for r in var.regions : replace(lower(r.name), "_", "-")
    ])) == length(var.regions)
    error_message = "regions must not list the same AWS region twice."
  }

  validation {
    condition = alltrue([
      for r in var.regions :
      can(regex("^[a-z]{2,}-[a-z]+-[0-9]+$", replace(lower(r.name), "_", "-")))
    ])
    error_message = "regions[].name must be a valid region name (e.g. us-east-1)."
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

variable "version_release_system" {
  description = "Atlas release channel. CONTINUOUS default keeps minor versions current (HybridRAG / vector search)."
  type        = string
  default     = "CONTINUOUS"

  validation {
    condition     = contains(["CONTINUOUS", "LTS"], var.version_release_system)
    error_message = "version_release_system must be CONTINUOUS or LTS."
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
  description = "App VPC for PrivateLink and Lambda. create=true manages one private VPC per cluster AWS region; create=false requires a full by_region entry per region. enable_nat_gateway turns on NAT in every managed region; single_nat_gateway shares one NAT across AZs (default true; set false for per-AZ HA). ecs_apps.*.internet_egress enables NAT per app region and HTTPS egress from the app security group."
  type = object({
    create             = optional(bool, true)
    base_cidr          = optional(string, "10.0.0.0/8")
    az_count           = optional(number, 2)
    enable_nat_gateway = optional(bool, false)
    single_nat_gateway = optional(bool, true)
    create_igw         = optional(bool, false)
    by_region = optional(map(object({
      cidr                    = optional(string)
      az_count                = optional(number)
      vpc_id                  = optional(string)
      private_subnet_ids      = optional(list(string), [])
      public_subnet_ids       = optional(list(string), [])
      vpc_cidr_block          = optional(string)
      private_route_table_ids = optional(list(string), [])
    })), {})
  })
  default = {}

  validation {
    condition = !var.vpc_config.create || (
      var.vpc_config.az_count >= 1 &&
      var.vpc_config.az_count <= 6 &&
      var.vpc_config.az_count == floor(var.vpc_config.az_count)
    )
    error_message = "vpc_config.az_count must be a whole number between 1 and 6 when create = true."
  }

  validation {
    condition = !var.vpc_config.create || alltrue([
      for _, cfg in var.vpc_config.by_region :
      cfg.az_count == null || (
        cfg.az_count >= 1 &&
        cfg.az_count <= 6 &&
        cfg.az_count == floor(cfg.az_count)
      )
    ])
    error_message = "vpc_config.by_region.*.az_count must be a whole number between 1 and 6 when create = true."
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
      length(cfg.public_subnet_ids) == 0 &&
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
        for i, region in distinct([for r in var.regions : replace(lower(r.name), "_", "-")]) :
        coalesce(try(var.vpc_config.by_region[region].cidr, null), cidrsubnet(var.vpc_config.base_cidr, 8, i))
      ])) == length(distinct([for r in var.regions : replace(lower(r.name), "_", "-")]))
    ) : true
    error_message = "Managed VPC CIDRs must be unique per cluster AWS region."
  }

  validation {
    condition     = !var.vpc_config.create || length(distinct([for r in var.regions : replace(lower(r.name), "_", "-")])) <= 256
    error_message = "Too many cluster AWS regions for vpc_config.base_cidr (max 256 /16 blocks from a /8 base)."
  }

  validation {
    condition = !var.vpc_config.create ? alltrue([
      for region in distinct([
        for _, edge in var.http_edges :
        coalesce(edge.aws_region, replace(lower(var.regions[0].name), "_", "-"))
      ]) :
      length(var.vpc_config.by_region[region].public_subnet_ids) > 0
    ]) : true
    error_message = "When vpc_config.create = false, public_subnet_ids is required in by_region for each http_edges region."
  }
}

# Atlas AWS integrations (CPA / encryption / log / backup)
# ----------------------------------------------------

variable "atlas_integrations" {
  description = <<-EOT
    Atlas AWS integrations (encryption, log export, backup export). Omit for production defaults (all enabled).
    encryption.kms_key_arn: BYO KMS; when set, create_kms_key is ignored.
    encryption.skip_private_endpoints: when true, omit Atlas KMS PrivateLink (private_endpoint_regions = []); default false enables KMS PE in every cluster AWS region.
    encryption.create_kms_key.region: primary KMS AWS region; defaults to regions[0] when omitted.
    encryption.create_kms_key.multi_region: defaults true (multi-Region primary CMK). Set false for a single-Region key; replica_regions must be empty.
    encryption.create_kms_key.replica_regions: inferred from cluster AWS regions except the primary when omitted; set explicitly to override.
    Log and backup export always use module-managed S3 buckets (name_prefix derived from default_resource_name_prefix).
    expiration_days maps to create_s3_bucket.expiration_days in atlas-aws.
    s3_force_destroy applies to both module-managed log and backup buckets (true for ephemeral demos; false for shared accounts that must retain objects).
  EOT
  type = object({
    encryption = optional(object({
      enabled                = optional(bool, true)
      kms_key_arn            = optional(string)
      skip_private_endpoints = optional(bool, false)
      create_kms_key = optional(object({
        deletion_window_in_days = optional(number, 7)
        enable_key_rotation     = optional(bool, true)
        multi_region            = optional(bool, true)
        region                  = optional(string)
        replica_regions         = optional(set(string))
      }), {})
    }), {})

    log_integration = optional(object({
      enabled = optional(bool, true)
      integrations = optional(list(object({
        log_types   = set(string)
        prefix_path = string
        })), [
        { log_types = ["MONGOD"], prefix_path = "operational" },
        { log_types = ["MONGOD_AUDIT"], prefix_path = "audit" },
      ])
      expiration_days = optional(number, 90)
    }), {})

    backup_export = optional(object({
      enabled         = optional(bool, true)
      expiration_days = optional(number, 365)
    }), {})

    s3_force_destroy = optional(bool, true)
  })
  default = {}
}

# Container registries
# ----------------------------------------------------

variable "ecr_repositories" {
  description = <<-EOT
    Optional ECR repositories managed by 01_lz. Independent of lambda_apps / ecs_apps / ec2_apps so registries survive compute changes.
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
  default = {}

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
      repo.lifecycle_keep_count >= 0 &&
      repo.lifecycle_keep_count == floor(repo.lifecycle_keep_count)
    ])
    error_message = "ecr_repositories.*.lifecycle_keep_count must be a whole number >= 0 (0 disables the lifecycle policy)."
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

# HTTP edge (ALB)
# ----------------------------------------------------

variable "http_edges" {
  description = <<-EOT
    Regional HTTP edges (ALB + CloudFront) owned by the landing zone. Map keys are stable identities (e.g. main).
    Public subnets and IGW are created per edge region when this map is non-empty.
    CloudFront terminates HTTPS on the default *.cloudfront.net domain; ALB is HTTP-only origin.
    Optional aliases + acm_certificate_arn enable a custom domain on CloudFront (cert must be in us-east-1; CNAME to cloudfront_domain).
  EOT
  type = map(object({
    aws_region          = optional(string)
    aliases             = optional(list(string), [])
    acm_certificate_arn = optional(string)
    idle_timeout        = optional(number, 60)
  }))
  default = {}

  validation {
    condition = alltrue([
      for _, edge in var.http_edges :
      contains(
        distinct([for r in var.regions : replace(lower(r.name), "_", "-")]),
        coalesce(edge.aws_region, replace(lower(var.regions[0].name), "_", "-"))
      )
    ])
    error_message = "http_edges.*.aws_region must be a cluster AWS region from regions."
  }

  validation {
    condition = alltrue([
      for _, edge in var.http_edges :
      length(edge.aliases) == 0 || edge.acm_certificate_arn != null
    ])
    error_message = "http_edges.*.aliases requires acm_certificate_arn."
  }

  validation {
    condition = alltrue([
      for _, edge in var.http_edges :
      edge.acm_certificate_arn == null || length(edge.aliases) > 0
    ])
    error_message = "http_edges.*.acm_certificate_arn requires aliases."
  }

  validation {
    condition = alltrue([
      for _, edge in var.http_edges :
      edge.acm_certificate_arn == null ||
      element(split(":", edge.acm_certificate_arn), 3) == "us-east-1"
    ])
    error_message = "http_edges.*.acm_certificate_arn must be in us-east-1 for CloudFront."
  }
}

# Apps
# ----------------------------------------------------

variable "lambda_apps" {
  description = <<-EOT
    Optional Lambda deployment targets. Map keys are stable identities.
    Each entry creates one IAM execution role and one Atlas IAM database user (username = that role ARN).
    ecr_key selects an entry in ecr_repositories (registry lifecycle is not tied to this map).
    roles maps to mongodbatlas_database_user.roles (multi-database / multi-role). role_name defaults to readWrite.
    primary_database is the DB_NAME for the app stack; defaults to roles[0].database_name.
    tfvars_path: relative path for a per-app infra.auto.tfvars writer; null/omit disables the file for that app.
    handoff_secret: null-gated Secrets Manager handoff for that app ({ name = optional } ; name defaults to <app-name>-app).
    Auth is IAM ROLE only in this example (no password, OIDC, or X.509).
  EOT
  type = map(object({
    name             = optional(string)
    ecr_key          = string
    aws_region       = optional(string)
    primary_database = optional(string)
    tfvars_path      = optional(string)
    handoff_secret = optional(object({
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
  description = <<-EOT
    Optional ECS deployment targets. Map keys are stable identities.
    Each entry creates one ECS task role, one execution role, and one Atlas IAM database user (username = task role ARN).
    ecr_key selects an entry in ecr_repositories. routing attaches the app to an http_edges ALB (02_app_ecs creates TG + listener rule).
    Omit routing for private/worker tasks or ECS without public HTTP. routing requires explicit edge, listener_priority, and path_pattern or host_header.
    tfvars_path: relative path for a per-app infra.auto.tfvars writer; null/omit disables the file for that app. Mutually exclusive with handoff_secret.
    handoff_secret: null-gated Secrets Manager handoff ({ name = optional } ; name defaults to <app-name>-app).
    container_env_vars: plain ECS environment entries merged into handoff (after Mongo aliases and Voyage base URL).
    container_secrets: BYO SM secret name lookups; resolved to ARNs in handoff with execution-role GetSecretValue.
    api_key_secret: null-gated managed HYBRIDRAG_API_KEY in SM (name defaults to <app-name>-api-key). Mutually exclusive with container_secrets.HYBRIDRAG_API_KEY.
    atlas_ai_model_api_key: when set, creates Atlas Voyage key + SM secret and wires VOYAGE_API_KEY / VOYAGE_BASE_URL into handoff.
    internet_egress: when true, enables a NAT gateway in the app's AWS region (managed VPC) and allows HTTPS egress to the public internet from the shared app security group.
  EOT
  type = map(object({
    name             = optional(string)
    ecr_key          = string
    aws_region       = optional(string)
    primary_database = optional(string)
    tfvars_path      = optional(string)
    routing = optional(object({
      edge              = string
      listener_priority = number
      path_pattern      = optional(list(string))
      host_header       = optional(list(string))
      container_port    = optional(number, 8000)
      health_check_path = optional(string, "/health")
    }))
    handoff_secret = optional(object({
      name = optional(string)
    }))
    container_env_vars = optional(map(string), {})
    container_secrets = optional(map(object({
      name     = string
      json_key = optional(string)
    })), {})
    api_key_secret = optional(object({
      name = optional(string)
    }))
    atlas_ai_model_api_key = optional(object({
      key_name = optional(string, "fastapi-minimal-voyage")
    }))
    internet_egress = optional(bool, false)
    roles = list(object({
      role_name       = optional(string, "readWrite")
      database_name   = string
      collection_name = optional(string)
    }))
  }))
  default = {}

  validation {
    condition     = alltrue([for _, app in var.ecs_apps : length(app.roles) > 0])
    error_message = "Each ecs_apps entry must include at least one roles entry."
  }

  validation {
    condition = alltrue([
      for _, app in var.ecs_apps :
      contains(keys(var.ecr_repositories), app.ecr_key)
    ])
    error_message = "Each ecs_apps.*.ecr_key must exist in ecr_repositories."
  }

  validation {
    condition = length(distinct([
      for _, app in var.ecs_apps : app.tfvars_path
      if app.tfvars_path != null && app.tfvars_path != ""
      ])) == length([
      for _, app in var.ecs_apps : app.tfvars_path
      if app.tfvars_path != null && app.tfvars_path != ""
    ])
    error_message = "ecs_apps.*.tfvars_path values must be unique when set."
  }

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

  validation {
    condition = alltrue([
      for _, app in var.ecs_apps :
      coalesce(app.aws_region, replace(lower(var.regions[0].name), "_", "-")) ==
      coalesce(
        try(var.ecr_repositories[app.ecr_key].region, null),
        replace(lower(var.regions[0].name), "_", "-")
      )
    ])
    error_message = "ecs_apps.*.aws_region must match ecr_repositories[ecr_key].region (after defaults)."
  }

  validation {
    condition = alltrue([
      for _, app in var.ecs_apps :
      app.routing == null || contains(keys(var.http_edges), app.routing.edge)
    ])
    error_message = "ecs_apps.*.routing.edge must reference a key in http_edges."
  }

  validation {
    condition = alltrue([
      for _, app in var.ecs_apps :
      app.routing == null || (
        length(coalesce(app.routing.path_pattern, [])) > 0 ||
        length(coalesce(app.routing.host_header, [])) > 0
      )
    ])
    error_message = "ecs_apps routing requires path_pattern or host_header."
  }

  validation {
    condition = length(distinct([
      for _, app in var.ecs_apps :
      "${app.routing.edge}:${app.routing.listener_priority}"
      if app.routing != null
      ])) == length([
      for _, app in var.ecs_apps :
      "${app.routing.edge}:${app.routing.listener_priority}"
      if app.routing != null
    ])
    error_message = "ecs_apps routing listener_priority must be unique per http_edges key."
  }

  validation {
    condition = alltrue([
      for _, app in var.ecs_apps :
      app.tfvars_path == null || app.tfvars_path == "" || app.handoff_secret == null
    ])
    error_message = "ecs_apps: tfvars_path and handoff_secret are mutually exclusive."
  }

  validation {
    condition = alltrue([
      for _, app in var.ecs_apps :
      app.api_key_secret == null || !contains(keys(app.container_secrets), "HYBRIDRAG_API_KEY")
    ])
    error_message = "ecs_apps: api_key_secret and container_secrets.HYBRIDRAG_API_KEY are mutually exclusive."
  }
}

variable "ec2_apps" {
  description = "Optional EC2 deployment targets (same shape as lambda_apps). No resources are created from this map yet."
  type = map(object({
    name             = optional(string)
    ecr_key          = string
    aws_region       = optional(string)
    primary_database = optional(string)
    tfvars_path      = optional(string)
    handoff_secret = optional(object({
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
      for _, app in var.ec2_apps :
      contains(
        distinct([for r in var.regions : replace(lower(r.name), "_", "-")]),
        coalesce(app.aws_region, replace(lower(var.regions[0].name), "_", "-"))
      )
    ])
    error_message = "ec2_apps.*.aws_region must be a cluster AWS region from regions."
  }
}
