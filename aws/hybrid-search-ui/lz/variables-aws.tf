# AWS app surface passed to modules/app-infra. The module owns the full schema
# for these inputs; see ../../modules/app-infra/variables.tf.

# --- ECS apps -----------------------------------------------------------------

variable "ecs_apps" {
  description = <<-EOT
    ECS apps on the shared VPC. The map key is the stable identity; each entry gets
    its own Atlas IAM database user, database, role, region, internet_egress, and
    routing. Add a second entry to run another app on the same cluster (the default
    keeps one UI). Full schema: ../../modules/app-infra/variables.tf.
  EOT
  type = map(object({
    name       = optional(string)
    ecr_key    = string
    aws_region = optional(string)
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

# --- HTTP edge ----------------------------------------------------------------

variable "http_edge" {
  description = <<-EOT
    Public HTTP entry point (ALB + CloudFront + WAF). Set enabled = false to skip all
    three when you only run the UI locally or reach it over PrivateLink; the app stack
    still deploys. custom_domain needs an ACM certificate in us-east-1 and its matching
    aliases.
  EOT
  type = object({
    enabled      = optional(bool, true)
    waf_disabled = optional(bool, false)
    custom_domain = optional(object({
      aliases             = list(string)
      acm_certificate_arn = string
    }))
  })
  default = {}
}

variable "skip_interface_endpoints" {
  description = <<-EOT
    Keep the five AWS interface VPC endpoints (ECR, logs, Secrets Manager, STS) out of
    the VPC. AWS API traffic then uses public endpoints over NAT, so this turns NAT on
    for the app. Atlas PrivateLink and the S3 gateway are unaffected. About $2.40/day
    off in us-east-1 with two AZs.
  EOT
  type        = bool
  default     = false
}
