variable "aws_region" {
  description = "AWS region (from 01_lz handoff)"
  type        = string
}

variable "private_subnet_ids" {
  description = "Private subnet IDs for Lambda VPC config"
  type        = list(string)
}

variable "lambda_security_group_id" {
  description = "Security group ID from 01_lz (restricted egress)"
  type        = string
}

variable "lambda_execution_role_arn" {
  description = "Lambda execution role ARN from 01_lz"
  type        = string
}

variable "mongo_private_connection_string" {
  description = "Private endpoint MongoDB connection string"
  type        = string
  sensitive   = true
}

variable "ecr_repository_url" {
  description = "ECR repository URL from 01_lz (no tag). Required; LZ creates the repo."
  type        = string
}

variable "name_prefix" {
  description = "Prefix for the Lambda function name"
  type        = string
  default     = "fastapi-minimal"
}

variable "image_tag" {
  description = "Container image tag to deploy"
  type        = string
  default     = "0.0.1"
}

variable "app_database_name" {
  description = "Database name passed to the Lambda as DB_NAME"
  type        = string
  default     = "test"
}

variable "tags" {
  description = "Tags applied to AWS resources"
  type        = map(string)
  default     = { Example = "aws-fastapi-minimal" }
}
