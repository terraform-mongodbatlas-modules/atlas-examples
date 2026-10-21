variable "name_suffix" {
  description = "Unique suffix for resource names (e.g. the GitHub run ID)"
  type        = string
}

variable "aws_region" {
  description = "AWS region for the networking resources"
  type        = string
  default     = "us-east-1"
}

variable "tags" {
  description = "Tags to apply to AWS resources"
  type        = map(string)
  default     = {}
}
