# Atlas inputs: organization, cluster shape, regions, and AWS integrations.
# autoembed_model lives here because the model is consumed by the Atlas autoEmbed
# vector index; its only AWS-side effect is the AUTOEMBED_MODEL container env in
# main.tf.

# --- Atlas --------------------------------------------------------------------

variable "atlas_org_id" {
  description = "MongoDB Atlas Organization ID."
  type        = string
}

variable "cluster_name" {
  description = "Atlas cluster name."
  type        = string
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

variable "autoembed_model" {
  description = "Atlas autoEmbed model used by the vector search index."
  type        = string
  default     = "voyage-4-lite"
}
