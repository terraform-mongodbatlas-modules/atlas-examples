variable "project_id" {
  description = "Atlas project ID."
  type        = string
}

variable "key_name" {
  description = "Name for the Atlas AI Model API key."
  type        = string
}

variable "secret_name" {
  description = "Secrets Manager secret name for the raw al-... key."
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
