variable "name" {
  description = "ECS cluster, service, task family, and container name."
  type        = string
}

variable "aws_region" {
  description = "AWS region for the cluster, service, and target group."
  type        = string
}

variable "ecr_repository_url" {
  description = "ECR repository URL. image_tag is appended."
  type        = string
}

variable "network" {
  description = "Private subnets and app security group from modules/app-infra ecs_apps.network."
  type = object({
    private_subnet_ids    = list(string)
    ecs_security_group_id = string
  })

  validation {
    condition     = length(var.network.private_subnet_ids) > 0
    error_message = "network.private_subnet_ids must contain at least one subnet."
  }
}

variable "iam" {
  description = "Task and execution role ARNs from modules/app-infra ecs_apps.iam."
  type = object({
    task_role_arn           = string
    task_execution_role_arn = string
  })
}

variable "routing" {
  description = "ALB listener rule and target group. Matches modules/app-infra ecs_apps.routing plus health_check_path (example merge)."
  type = object({
    listener_arn      = string
    listener_priority = number
    path_pattern      = optional(list(string), [])
    host_header       = optional(list(string), [])
    container_port    = optional(number, 8000)
    health_check_path = optional(string, "/health")
  })

  validation {
    condition     = var.routing.listener_priority >= 1 && var.routing.listener_priority <= 50000
    error_message = "routing.listener_priority must be between 1 and 50000."
  }

  validation {
    condition     = var.routing.container_port >= 1 && var.routing.container_port <= 65535
    error_message = "routing.container_port must be between 1 and 65535."
  }

  validation {
    condition = (
      length(var.routing.path_pattern) > 0 ||
      length(var.routing.host_header) > 0
    )
    error_message = "routing must set path_pattern or host_header so the listener rule has a condition."
  }
}

variable "container" {
  description = "Example-owned env and SM JSON keys. secret_arn is required when secret_keys is non-empty. Task secrets use valueFrom = \"<secret_arn>:<key>::\"."
  type = object({
    env         = optional(map(string), {})
    secret_keys = optional(list(string), [])
    secret_arn  = optional(string, "")
  })
  default = {}

  validation {
    condition     = length(var.container.secret_keys) == 0 || startswith(var.container.secret_arn, "arn:")
    error_message = "container.secret_arn is required when container.secret_keys is set."
  }
}

variable "task_cpu" {
  description = "Fargate task CPU units."
  type        = string
  default     = "512"
}

variable "task_memory" {
  description = "Fargate task memory MiB."
  type        = string
  default     = "1024"
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

variable "deployment_minimum_healthy_percent" {
  description = "Lower bound on the percentage of desired tasks that must stay healthy during a rolling deploy. 100 keeps the old tasks serving until new ones are healthy."
  type        = number
  default     = 100

  validation {
    condition     = var.deployment_minimum_healthy_percent >= 0 && var.deployment_minimum_healthy_percent <= 100
    error_message = "deployment_minimum_healthy_percent must be between 0 and 100."
  }
}

variable "deployment_maximum_percent" {
  description = "Upper bound on the percentage of desired tasks allowed during a rolling deploy. 200 lets ECS start a replacement task before draining the old one."
  type        = number
  default     = 200

  validation {
    condition     = var.deployment_maximum_percent >= 100
    error_message = "deployment_maximum_percent must be at least 100."
  }
}

variable "deployment_circuit_breaker_enabled" {
  description = "Enable the ECS deployment circuit breaker. A failed deploy rolls back instead of leaving a half-updated service."
  type        = bool
  default     = true
}

variable "deployment_circuit_breaker_rollback" {
  description = "Roll back to the last stable task definition when the circuit breaker trips."
  type        = bool
  default     = true
}

variable "deregistration_delay" {
  description = "Seconds the target group waits for in-flight requests to drain before deregistering a target during a deploy."
  type        = number
  default     = 30
}

variable "deployment_timeout" {
  description = "Maximum time to wait for the ECS service create, update, or delete. Terraform duration string, e.g. 15m."
  type        = string
  default     = "15m"
}

variable "health_check_grace_period_seconds" {
  description = "Seconds to ignore failing ALB health checks after a task starts. Default 30 suits a fast-booting app; index or migration work belongs in a separate one-shot task, not in service startup."
  type        = number
  default     = 30

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
