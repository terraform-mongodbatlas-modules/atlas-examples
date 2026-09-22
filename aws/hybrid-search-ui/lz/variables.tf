variable "atlas_org_id" {
  description = "MongoDB Atlas Organization ID."
  type        = string
}

variable "cluster_name" {
  description = "Atlas cluster name."
  type        = string
}

variable "default_resource_name_prefix" {
  description = "Prefix for Atlas project name and AWS resource names (VPC, security groups, module-managed S3 buckets)."
  type        = string
  default     = "hybrid-search-ui"
}

variable "public_debug_access" {
  description = "Opt-in public internet access for debugging (SCRAM + IP allowlist). Null disables."
  type = object({
    ip_address    = string
    username      = optional(string, "debug")
    password      = optional(string)
    database_name = optional(string, "hybrid_search")
    role_name     = optional(string, "readWrite")
    comment       = optional(string, "public debug")
  })
  default  = null
  nullable = true
}

variable "tags" {
  description = "Tags applied to Atlas and AWS resources."
  type        = map(string)
  default     = { Example = "aws-hybrid-search-ui" }
}

variable "regions" {
  description = "Cluster regions. Use AWS region names (e.g. us-east-1). Atlas format (US_EAST_1) is also accepted."
  type = list(object({
    name       = string
    node_count = optional(number, 3)
  }))
  default = [{ name = "us-east-1", node_count = 3 }]
}

variable "cluster_type" {
  description = "Atlas cluster type. Default SHARDED. Set REPLICASET for cheaper personal labs."
  type        = string
  default     = "SHARDED"
}

variable "shard_count" {
  description = "Shard count when cluster_type = SHARDED. Ignored for REPLICASET."
  type        = number
  default     = 1
}

variable "manual_scaling" {
  description = "Null keeps compute auto-scaling (M10 to M200). Set instance_size to pin (disk GB still auto-scales)."
  type = object({
    instance_size = string
  })
  default  = null
  nullable = true
}

variable "vpc_config" {
  description = "App VPC for PrivateLink and ECS. Composition input for modules/app-infra; that module validates the value. bedrock_runtime_endpoint overrides the inferred bedrock-runtime endpoint (null infers it from the LLM provider)."
  type = object({
    create                   = optional(bool, true)
    base_cidr                = optional(string, "10.0.0.0/8")
    az_count                 = optional(number, 2)
    enable_nat_gateway       = optional(bool, false)
    single_nat_gateway       = optional(bool, true)
    create_igw               = optional(bool, false)
    skip_interface_endpoints = optional(bool, false)
    bedrock_runtime_endpoint = optional(bool)
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
}

variable "atlas_integrations" {
  description = "Atlas AWS integrations (encryption, log export, backup export). Consumed here, not by modules/app-infra."
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
        { log_types = ["MONGOD", "MONGOD_AUDIT"], prefix_path = "logs" },
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

variable "ecr_repositories" {
  description = "ECR repositories. Composition input for modules/app-infra."
  type = map(object({
    name                 = optional(string)
    region               = optional(string)
    image_tag_mutability = optional(string, "IMMUTABLE")
    scan_on_push         = optional(bool, true)
    force_delete         = optional(bool, true)
    lifecycle_keep_count = optional(number, 10)
  }))
  default = {
    ui = { name = "hybrid-search-ui" }
  }
}

variable "http_edges" {
  description = "HTTP edges (ALB + CloudFront + WAF). Composition input for modules/app-infra. Set http_edges = {} (see terraform.tfvars.example) to skip ALB, CloudFront, and WAF when you only run the UI locally."
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
  default = {
    main = {}
  }
}

variable "ecs_apps" {
  description = "ECS apps. Composition input for modules/app-infra. Default UI on port 8001."
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
  }))
  default = {
    ui = {
      name            = "hybrid-search-ui"
      ecr_key         = "ui"
      internet_egress = false
      routing = {
        edge              = "main"
        listener_priority = 100
        path_pattern      = ["/*"]
        container_port    = 8001
      }
      roles = [{ database_name = "hybrid_search" }]
    }
  }
}

variable "llm_secret_name" {
  description = "Optional Secrets Manager secret name holding a raw LLM API key (just create-llm-secret). When set, the value is inlined into the app secret JSON and the provider is inferred from llm_env_name. Leave null to use the default bedrock provider, which needs no key. Validation lives in modules/llm."
  type        = string
  default     = null
  nullable    = true
}

variable "llm_provider" {
  description = "LLM provider when llm_secret_name is null. Null defaults to bedrock, which uses the ECS task role and needs no API key. When llm_secret_name is set and this is set, it must match the provider that llm_env_name infers."
  type        = string
  default     = null
  nullable    = true
}

variable "enable_llm" {
  description = "Set false for search-only: no LLM answer, no provider inputs consumed, and no bedrock-runtime interface endpoint."
  type        = bool
  default     = true
}

variable "llm_env_name" {
  description = "Container env name for the optional LLM key. Infers the provider when llm_secret_name is set: ANTHROPIC_API_KEY=anthropic, OPENAI_API_KEY=openai, GEMINI_API_KEY=gemini, GROVE_API_KEY=grove. Ignored when llm_secret_name is null."
  type        = string
  default     = "ANTHROPIC_API_KEY"
}

variable "llm_env" {
  description = "Extra LLM values inlined into the app secret JSON (ANTHROPIC_MODEL, BEDROCK_MODEL, GEMINI_MODEL, OPENAI_MODEL, OPENAI_BASE_URL, OPENAI_EXTRA_HEADERS, GROVE_BASE_URL, GROVE_MODEL). Do not put the API key here; use llm_secret_name. AWS_REGION is set from regions[0] for the bedrock provider; set llm_env.BEDROCK_MODEL to override the model."
  type        = map(string)
  default     = {}
}

variable "autoembed_model" {
  description = "Atlas autoEmbed model used by the vector search index."
  type        = string
  default     = "voyage-4-lite"
}
