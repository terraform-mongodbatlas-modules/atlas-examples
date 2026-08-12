variable "secret_name" {
  description = "Secrets Manager secret name for the API key."
  type        = string
}

variable "aws_region" {
  description = "AWS region for the Secrets Manager secret."
  type        = string
}

variable "tags" {
  description = "Tags applied to AWS resources."
  type        = map(string)
  default     = {}
}
