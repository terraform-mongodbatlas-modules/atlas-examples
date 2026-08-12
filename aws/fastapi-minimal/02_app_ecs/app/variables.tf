variable "handoff_secret_name" {
  description = "SM secret name written by 01_lz (ecs_apps.*.handoff_secret). When set, infra and env fields come from the JSON payload."
  type        = string
  default     = null
  nullable    = true

  validation {
    condition = var.handoff_secret_name != null || (
      var.aws_region != null &&
      var.private_subnet_ids != null && length(var.private_subnet_ids) > 0 &&
      var.ecs_security_group_id != null &&
      var.ecs_task_role_arn != null &&
      var.ecs_task_execution_role_arn != null &&
      var.mongo_private_connection_string != null &&
      var.ecr_repository_url != null &&
      var.alb_listener_arn != null &&
      var.alb_dns_name != null &&
      var.listener_priority != null
    )
    error_message = "Set handoff_secret_name or supply all flat infra variables (legacy tfvars path)."
  }
}

variable "aws_region" {
  description = "AWS region (from 01_lz handoff or provider default when using handoff_secret_name)"
  type        = string
  default     = null
  nullable    = true
}

variable "private_subnet_ids" {
  description = "Private subnet IDs for ECS tasks"
  type        = list(string)
  default     = null
  nullable    = true
}

variable "ecs_security_group_id" {
  description = "Shared app security group ID from 01_lz"
  type        = string
  default     = null
  nullable    = true
}

variable "ecs_task_role_arn" {
  description = "ECS task role ARN from 01_lz (Atlas IAM auth)"
  type        = string
  default     = null
  nullable    = true
}

variable "ecs_task_execution_role_arn" {
  description = "ECS task execution role ARN from 01_lz"
  type        = string
  default     = null
  nullable    = true
}

variable "mongo_private_connection_string" {
  description = "PrivateLink MongoDB SRV from 01_lz handoff with IAM auth query params"
  type        = string
  sensitive   = true
  default     = null
  nullable    = true
}

variable "ecr_repository_url" {
  description = "ECR repository URL from 01_lz without an image tag."
  type        = string
  default     = null
  nullable    = true

  validation {
    condition = (
      var.ecr_repository_url == null ||
      (
        var.ecr_repository_url == trimspace(var.ecr_repository_url) &&
        length(var.ecr_repository_url) > 0 &&
        !strcontains(element(reverse(split("/", var.ecr_repository_url)), 0), ":")
      )
    )
    error_message = "ecr_repository_url must be a non-empty, untagged ECR repository URL. Set image_tag separately."
  }
}

variable "alb_listener_arn" {
  description = "ALB listener ARN from 01_lz http_edges handoff"
  type        = string
  default     = null
  nullable    = true
}

variable "alb_dns_name" {
  description = "ALB DNS name from 01_lz (for smoke tests)"
  type        = string
  default     = null
  nullable    = true
}

variable "listener_priority" {
  description = "ALB listener rule priority from 01_lz routing"
  type        = number
  default     = null
  nullable    = true
}

variable "path_pattern" {
  description = "ALB path patterns from 01_lz routing"
  type        = list(string)
  default     = null
  nullable    = true
}

variable "host_header" {
  description = "ALB host headers from 01_lz routing"
  type        = list(string)
  default     = []
}

variable "container_port" {
  description = "Container port from 01_lz routing"
  type        = number
  default     = null
  nullable    = true
}

variable "health_check_path" {
  description = "Target group health check path from 01_lz routing"
  type        = string
  default     = null
  nullable    = true
}

variable "container_env_vars" {
  description = "Extra plain environment variables from 01_lz handoff"
  type        = map(string)
  default     = null
  nullable    = true
}

variable "container_secret_env_vars" {
  description = "Secret-backed environment variables (env name to SM ARN) from 01_lz handoff"
  type        = map(string)
  default     = null
  nullable    = true
}

variable "wait_for_steady_state" {
  description = "When true, block apply until the ECS service reaches steady state (running tasks and healthy ALB targets)."
  type        = bool
  default     = true
}

variable "deployment_timeout" {
  description = "Maximum time to wait for the ECS service create, update, or delete (including steady-state polling when wait_for_steady_state is true). Terraform duration string, e.g. 15m."
  type        = string
  default     = "15m"
}

variable "health_check_grace_period_seconds" {
  description = "Seconds to ignore failing ALB health checks after a task starts. HybridRAG cold start can exceed 2 minutes (tiktoken download, Mongo init)."
  type        = number
  default     = 300

  validation {
    condition     = var.health_check_grace_period_seconds >= 0
    error_message = "health_check_grace_period_seconds must be zero or positive."
  }
}

variable "name_prefix" {
  description = "Prefix for ECS resource names"
  type        = string
  default     = null
  nullable    = true
}

variable "image_tag" {
  description = "Container image tag to deploy"
  type        = string
  default     = "0.0.1"
}

variable "app_database_name" {
  description = "Database name passed to the container as DB_NAME"
  type        = string
  default     = null
  nullable    = true
}

variable "tags" {
  description = "Tags applied to AWS resources"
  type        = map(string)
  default     = { Example = "aws-fastapi-minimal" }
}
