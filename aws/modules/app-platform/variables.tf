variable "default_resource_name_prefix" {
  description = "Prefix for AWS resource names (VPC, security groups, app roles, HTTP edge)."
  type        = string
  default     = "lz"
}

variable "tags" {
  description = "Tags applied to AWS resources."
  type        = map(string)
  default     = {}
}

variable "regions" {
  description = "Cluster regions. Use AWS region names (e.g. us-east-1). Atlas format (US_EAST_1) is also accepted. One VPC is created per region on the managed path."
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

variable "vpc_config" {
  description = "App VPC for PrivateLink and ECS. create=true manages one private VPC per cluster AWS region; create=false requires a full by_region entry per region. enable_nat_gateway turns on NAT in every managed region; single_nat_gateway shares one NAT across AZs (default true; set false for per-AZ HA). ecs_apps.*.internet_egress enables NAT per app region and HTTPS egress from the app security group. skip_interface_endpoints omits interface endpoints for ecr.api, ecr.dkr, logs, secretsmanager, and sts (requires NAT so Fargate can reach those APIs over public HTTPS). bedrock_runtime_endpoint adds a bedrock-runtime interface endpoint for Bedrock inference (Converse), with a VPC endpoint policy restricted to the Converse and InvokeModel actions; it bills per AZ-hour. It is inaccessible while skip_interface_endpoints = true. No bedrock control-plane endpoint is created because the app only calls the runtime API. Does not skip the S3 gateway endpoint or Atlas PrivateLink."
  type = object({
    create                   = optional(bool, true)
    base_cidr                = optional(string, "10.0.0.0/8")
    az_count                 = optional(number, 2)
    enable_nat_gateway       = optional(bool, false)
    single_nat_gateway       = optional(bool, true)
    create_igw               = optional(bool, false)
    skip_interface_endpoints = optional(bool, false)
    bedrock_runtime_endpoint = optional(bool, false)
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

variable "ecr_repositories" {
  description = <<-EOT
    Optional ECR repositories. Map keys are stable identities. Each entry creates a repository; lifecycle_keep_count > 0 adds a lifecycle policy (keep last N images).
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

variable "http_edges" {
  description = <<-EOT
    Regional HTTP edges (ALB + CloudFront + WAF). Map keys are stable identities (e.g. main).
    Public subnets and IGW are created per edge region when this map is non-empty.
    CloudFront terminates HTTPS on the default *.cloudfront.net domain; ALB is HTTP-only origin, restricted to the CloudFront origin-facing prefix list.
    idle_timeout defaults 120 (ALB). Nested http_edge sets CloudFront origin_read_timeout to 120 to match.
    waf.enabled defaults true (AWS Managed Rules Common Rule Set). Set waf = { enabled = false } to skip.
    waf.common_rule_set_count_rules counts named CRS rules (for example SizeRestrictions_BODY for file uploads). Empty by default.
    Optional aliases + acm_certificate_arn enable a custom domain on CloudFront (cert must be in us-east-1; CNAME to cloudfront_domain).
  EOT
  type = map(object({
    aws_region          = optional(string)
    aliases             = optional(list(string), [])
    acm_certificate_arn = optional(string)
    idle_timeout        = optional(number, 120)
    waf = optional(object({
      enabled                     = optional(bool, true)
      common_rule_set_count_rules = optional(list(string), [])
    }), {})
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

variable "ecs_apps" {
  description = <<-EOT
    Optional ECS deployment targets. Map keys are stable identities.
    Each entry creates one ECS task role and one execution role. The caller owns the Atlas IAM database user (username = task role ARN).
    ecr_key selects an entry in ecr_repositories. routing attaches the app to an http_edges ALB (ecs-service creates TG + listener rule).
    Omit routing for private/worker tasks. routing requires explicit edge, listener_priority, and path_pattern or host_header.
    internet_egress: when true, enables a NAT gateway in the app's AWS region (managed VPC) and allows HTTPS egress to the public internet from the shared app security group.
    extra_task_policies: IAM task-role policies the caller authors, keyed by policy name. The caller passes JSON it owns (for example from a provider module); this module only attaches it.
  EOT
  type = map(object({
    name             = optional(string)
    ecr_key          = string
    aws_region       = optional(string)
    primary_database = optional(string)
    routing = optional(object({
      edge              = string
      listener_priority = number
      path_pattern      = optional(list(string))
      host_header       = optional(list(string))
      container_port    = optional(number, 8000)
    }))
    internet_egress = optional(bool, false)
    roles = list(object({
      role_name       = optional(string, "readWrite")
      database_name   = string
      collection_name = optional(string)
    }))
    extra_task_policies = optional(map(string), {})
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
}
