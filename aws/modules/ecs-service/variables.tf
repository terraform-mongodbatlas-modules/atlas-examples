variable "handoff_secret_name" {
  description = "Secrets Manager secret name written by the example lz stack. Infra and env fields come from the JSON payload."
  type        = string
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
