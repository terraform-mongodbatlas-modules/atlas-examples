variable "handoff" {
  description = "Decoded lz payload. Extra JSON keys are stripped. secret_arn is required when container_secret_keys is set."
  type = object({
    aws_region                      = string
    name                            = string
    private_subnet_ids              = list(string)
    ecs_security_group_id           = string
    ecs_task_role_arn               = string
    ecs_task_execution_role_arn     = string
    mongo_private_connection_string = string
    app_database_name               = string
    ecr_repository_url              = string
    alb_listener_arn                = string
    listener_priority               = number
    path_pattern                    = optional(list(string), [])
    host_header                     = optional(list(string), [])
    container_port                  = optional(number, 8000)
    health_check_path               = optional(string, "/health")
    container_env_vars              = optional(map(string), {})
    container_secret_keys           = optional(list(string), [])
    secret_arn                      = optional(string, "")
    origin_header_name              = optional(string, "")
    origin_header_value             = optional(string, "")
    task_cpu                        = optional(string, "512")
    task_memory                     = optional(string, "1024")
  })

  validation {
    condition     = length(var.handoff.private_subnet_ids) > 0
    error_message = "handoff.private_subnet_ids must contain at least one subnet."
  }

  validation {
    condition     = var.handoff.listener_priority >= 1 && var.handoff.listener_priority <= 50000
    error_message = "handoff.listener_priority must be between 1 and 50000."
  }

  validation {
    condition     = var.handoff.container_port >= 1 && var.handoff.container_port <= 65535
    error_message = "handoff.container_port must be between 1 and 65535."
  }

  validation {
    condition = (
      length(var.handoff.path_pattern) > 0 ||
      length(var.handoff.host_header) > 0 ||
      var.handoff.origin_header_name != ""
    )
    error_message = "handoff must set path_pattern, host_header, or origin_header_name so the listener rule has a condition."
  }

  validation {
    condition     = var.handoff.origin_header_name == "" || var.handoff.origin_header_value != ""
    error_message = "handoff.origin_header_value is required when origin_header_name is set."
  }

  validation {
    condition     = length(var.handoff.container_secret_keys) == 0 || startswith(var.handoff.secret_arn, "arn:")
    error_message = "handoff.secret_arn is required when container_secret_keys is set."
  }
}

variable "image_tag" {
  description = "Container image tag to deploy."
  type        = string
  default     = "0.0.1"
}

variable "wait_for_steady_state" {
  description = "When true, block apply until the ECS service reaches steady state (running tasks and healthy ALB targets)."
  type        = bool
  default     = true
}

variable "deployment_timeout" {
  description = "Maximum time to wait for the ECS service create, update, or delete. Terraform duration string, e.g. 15m."
  type        = string
  default     = "15m"
}

variable "health_check_grace_period_seconds" {
  description = "Seconds to ignore failing ALB health checks after a task starts."
  type        = number
  default     = 300

  validation {
    condition     = var.health_check_grace_period_seconds >= 0
    error_message = "health_check_grace_period_seconds must be zero or positive."
  }
}

variable "tags" {
  description = "Tags applied to AWS resources."
  type        = map(string)
  default     = {}
}
