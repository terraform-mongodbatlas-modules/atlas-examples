variable "aws_region" {
  description = "AWS region (from 01_lz handoff)"
  type        = string
}

variable "private_subnet_ids" {
  description = "Private subnet IDs for ECS tasks"
  type        = list(string)

  validation {
    condition     = length(var.private_subnet_ids) > 0
    error_message = "private_subnet_ids must contain at least one subnet."
  }
}

variable "ecs_security_group_id" {
  description = "Shared app security group ID from 01_lz"
  type        = string
}

variable "ecs_task_role_arn" {
  description = "ECS task role ARN from 01_lz (Atlas IAM auth)"
  type        = string
}

variable "ecs_task_execution_role_arn" {
  description = "ECS task execution role ARN from 01_lz"
  type        = string
}

variable "mongo_private_connection_string" {
  description = "PrivateLink MongoDB SRV from 01_lz handoff with authSource=$external and authMechanism=MONGODB-AWS query params"
  type        = string
  sensitive   = true
}

variable "ecr_repository_url" {
  description = "ECR repository URL from 01_lz without an image tag."
  type        = string
  nullable    = false

  validation {
    condition = (
      var.ecr_repository_url == trimspace(var.ecr_repository_url) &&
      length(var.ecr_repository_url) > 0 &&
      !strcontains(element(reverse(split("/", var.ecr_repository_url)), 0), ":")
    )
    error_message = "ecr_repository_url must be a non-empty, untagged ECR repository URL. Set image_tag separately."
  }
}

variable "alb_listener_arn" {
  description = "ALB listener ARN from 01_lz http_edges handoff"
  type        = string
}

variable "alb_dns_name" {
  description = "ALB DNS name from 01_lz (for smoke tests)"
  type        = string
}

variable "listener_priority" {
  description = "ALB listener rule priority from 01_lz routing"
  type        = number
}

variable "path_pattern" {
  description = "ALB path patterns from 01_lz routing"
  type        = list(string)
  default     = []
}

variable "host_header" {
  description = "ALB host headers from 01_lz routing"
  type        = list(string)
  default     = []
}

variable "container_port" {
  description = "Container port from 01_lz routing"
  type        = number
  default     = 8000
}

variable "health_check_path" {
  description = "Target group health check path from 01_lz routing"
  type        = string
  default     = "/"
}

variable "wait_for_steady_state" {
  description = "When true, block apply until the ECS service reaches steady state (running tasks and healthy ALB targets)."
  type        = bool
  default     = true
}

variable "health_check_grace_period_seconds" {
  description = "Seconds to ignore failing ALB health checks after a task starts (uvicorn/Mongo startup)."
  type        = number
  default     = 120

  validation {
    condition     = var.health_check_grace_period_seconds >= 0
    error_message = "health_check_grace_period_seconds must be zero or positive."
  }
}

variable "name_prefix" {
  description = "Prefix for ECS resource names"
  type        = string
  default     = "fastapi-minimal"
}

variable "image_tag" {
  description = "Container image tag to deploy"
  type        = string
  default     = "0.0.1"
}

variable "app_database_name" {
  description = "Database name passed to the container as DB_NAME"
  type        = string
  default     = "test"
}

variable "tags" {
  description = "Tags applied to AWS resources"
  type        = map(string)
  default     = { Example = "aws-fastapi-minimal" }
}
