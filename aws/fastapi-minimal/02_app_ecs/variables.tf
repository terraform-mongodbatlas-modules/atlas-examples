variable "aws_region" {
  description = "AWS region (from 01_lz handoff)"
  type        = string
}

variable "public_subnet_ids" {
  description = "Public subnet IDs for internet-facing ALB"
  type        = list(string)

  validation {
    condition     = length(var.public_subnet_ids) > 0
    error_message = "public_subnet_ids must contain at least one subnet."
  }
}

variable "private_subnet_ids" {
  description = "Private subnet IDs for ECS tasks"
  type        = list(string)

  validation {
    condition     = length(var.private_subnet_ids) > 0
    error_message = "private_subnet_ids must contain at least one subnet."
  }
}

variable "ecs_security_group_id" {
  description = "Shared app security group ID from 01_lz"
  type        = string
}

variable "ecs_task_role_arn" {
  description = "ECS task role ARN from 01_lz (Atlas IAM auth)"
  type        = string
}

variable "ecs_task_execution_role_arn" {
  description = "ECS task execution role ARN from 01_lz"
  type        = string
}

variable "mongo_private_connection_string" {
  description = "Private endpoint MongoDB connection string"
  type        = string
  sensitive   = true
}

variable "ecr_repository_url" {
  description = "ECR repository URL from 01_lz without an image tag."
  type        = string
  nullable    = false

  validation {
    condition = (
      var.ecr_repository_url == trimspace(var.ecr_repository_url) &&
      length(var.ecr_repository_url) > 0 &&
      !strcontains(element(reverse(split("/", var.ecr_repository_url)), 0), ":")
    )
    error_message = "ecr_repository_url must be a non-empty, untagged ECR repository URL. Set image_tag separately."
  }
}

variable "name_prefix" {
  description = "Prefix for ECS and ALB resource names"
  type        = string
  default     = "fastapi-minimal"
}

variable "image_tag" {
  description = "Container image tag to deploy"
  type        = string
  default     = "0.0.1"
}

variable "app_database_name" {
  description = "Database name passed to the container as DB_NAME"
  type        = string
  default     = "test"
}

variable "tags" {
  description = "Tags applied to AWS resources"
  type        = map(string)
  default     = { Example = "aws-fastapi-minimal" }
}
