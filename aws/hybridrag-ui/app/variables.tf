variable "app_secret_name" {
  description = "Secrets Manager secret name written by the lz stack."
  type        = string
  default     = "hybridrag-ui-app"
}

variable "image_tag" {
  description = "Container image tag pushed by just build-push."
  type        = string
  default     = "0.0.1"
}

variable "task_cpu" {
  description = "Fargate task CPU units."
  type        = string
  default     = "1024"
}

variable "task_memory" {
  description = "Fargate task memory MiB."
  type        = string
  default     = "2048"
}

variable "tags" {
  description = "Tags applied to AWS resources."
  type        = map(string)
  default     = { Example = "aws-hybridrag-ui" }
}
