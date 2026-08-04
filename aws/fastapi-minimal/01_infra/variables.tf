variable "atlas_org_id" {
  description = "MongoDB Atlas Organization ID"
  type        = string
}

variable "atlas_region" {
  description = "Atlas region name (e.g. US_EAST_1). AWS region is derived automatically."
  type        = string
  default     = "US_EAST_1"
}

variable "name_prefix" {
  description = "Prefix for project, cluster, VPC, and IAM role names"
  type        = string
  default     = "fastapi-minimal"
}

variable "tags" {
  description = "Tags applied to Atlas and AWS resources"
  type        = map(string)
  default     = { Example = "aws-fastapi-minimal" }
}

variable "s3_force_destroy" {
  description = "Force-destroy module-managed log and backup export S3 buckets even when non-empty. Enable for ephemeral demos; disable for shared accounts that must retain objects."
  type        = bool
  default     = true
}
