variable "handoff_secret_name" {
  description = "SM secret name from 01_lz ecs_apps.hybridrag_ui handoff (default hybridrag-ui-app)."
  type        = string
}

variable "image_tag" {
  description = "Container image tag to deploy"
  type        = string
  default     = "0.0.1"
}

variable "wait_for_steady_state" {
  description = "Block apply until the ECS service reaches steady state."
  type        = bool
  default     = true
}

variable "deployment_timeout" {
  description = "Max wait for ECS service create, update, or delete."
  type        = string
  default     = "15m"
}

variable "health_check_grace_period_seconds" {
  description = "Seconds to ignore failing ALB health checks after task start."
  type        = number
  default     = 300

  validation {
    condition     = var.health_check_grace_period_seconds >= 0
    error_message = "health_check_grace_period_seconds must be zero or positive."
  }
}

variable "tags" {
  description = "Tags applied to AWS resources"
  type        = map(string)
  default     = { Example = "aws-fastapi-minimal" }
}
