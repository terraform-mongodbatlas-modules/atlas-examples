# Shared example variables: resource names, tags, and opt-in debug access.
# Atlas inputs are in variables-atlas.tf, the AWS app surface in
# variables-aws.tf, and the LLM bundle in variables-llm.tf.

# --- Shared -------------------------------------------------------------------

variable "default_resource_name_prefix" {
  description = "Prefix for Atlas project name and AWS resource names (VPC, security groups, module-managed S3 buckets)."
  type        = string
  default     = "hybrid-search-ui"
}

variable "tags" {
  description = "Tags applied to Atlas and AWS resources."
  type        = map(string)
  default     = { Example = "aws-hybrid-search-ui" }
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
