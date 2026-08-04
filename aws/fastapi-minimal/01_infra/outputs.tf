output "aws_region" {
  description = "AWS region derived from atlas_region"
  value       = local.aws_region
}

output "vpc_id" {
  description = "VPC ID for 02_app_lambda"
  value       = module.vpc.vpc_id
}

output "private_subnet_ids" {
  description = "Private subnet IDs for Lambda and PrivateLink"
  value       = module.vpc.private_subnets
}

output "lambda_security_group_id" {
  description = "Security group ID for the Lambda function"
  value       = aws_security_group.lambda.id
}

output "lambda_execution_role_arn" {
  description = "IAM role ARN for Lambda (also the Atlas IAM DB username)"
  value       = aws_iam_role.lambda_exec.arn
}

output "mongo_private_connection_string" {
  description = "Private endpoint SRV connection string for the cluster"
  sensitive   = true
  value       = local.mongo_private_connection_string
}

output "atlas_project_id" {
  description = "Atlas project ID"
  value       = module.atlas_project.id
}

output "atlas_cluster_name" {
  description = "Atlas cluster name"
  value       = module.atlas_cluster.cluster_name
}

output "app_database_name" {
  description = "Database granted to the Lambda IAM user (readWrite)"
  value       = local.app_database_name
}

output "privatelink" {
  description = "PrivateLink endpoint summary"
  value       = module.atlas_aws.privatelink
}

output "log_integration_bucket_name" {
  description = "Log integration S3 bucket name"
  value       = try(module.atlas_aws.log_integration.bucket_name, null)
}

output "backup_export_bucket_name" {
  description = "Backup export S3 bucket name"
  value       = try(module.atlas_aws.backup_export.bucket_name, null)
}

