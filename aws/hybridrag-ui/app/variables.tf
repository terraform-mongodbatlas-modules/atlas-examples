variable "handoff_secret_name" {
  description = "Secrets Manager secret name written by the lz stack."
  type        = string
}

variable "image_tag" {
  description = "Container image tag pushed by just build-push."
  type        = string
  default     = "0.0.1"
}

variable "tags" {
  description = "Tags applied to AWS resources."
  type        = map(string)
  default     = { Example = "aws-hybridrag-ui" }
}
