output "aws_region" {
  description = "AWS region derived from regions[0].name"
  value       = local.aws_region
}

output "vpc_id" {
  description = "VPC ID for 02_app_lambda"
  value       = local.vpc_id
}

output "private_subnet_ids" {
  description = "Private subnet IDs for Lambda and PrivateLink"
  value       = local.private_subnet_ids
}

output "lambda_security_group_id" {
  description = "Security group ID for the primary lambda_apps entry"
  value       = aws_security_group.lambda[local.primary_app.aws_region].id
}

output "lambda_execution_role_arn" {
  description = "Primary lambda_apps IAM role ARN (Atlas IAM DB username for that app)"
  value       = aws_iam_role.lambda_exec[local.primary_app_key].arn
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
  description = "Primary lambda_apps primary_database (DB_NAME handoff)"
  value       = local.primary_app.primary_database
}

output "ecr_repository_url" {
  description = "ECR URL for the primary lambda_apps ecr_key (handoff convenience)"
  value       = local.primary_ecr_url
}

output "ecr_repository_urls" {
  description = "Map of ecr_repositories key to repository URL"
  value       = { for k, r in aws_ecr_repository.this : k => r.repository_url }
}

output "ecr_repositories" {
  description = "Resolved ecr_repositories (name, URL, scan/lifecycle settings)"
  value = {
    for k, v in local.ecr_repositories : k => {
      name                 = v.name
      region               = v.region
      repository_url       = aws_ecr_repository.this[k].repository_url
      image_tag_mutability = v.image_tag_mutability
      scan_on_push         = v.scan_on_push
      force_delete         = v.force_delete
      lifecycle_keep_count = v.lifecycle_keep_count
    }
  }
}

output "lambda_apps" {
  description = "Resolved lambda_apps (name, primary_database, roles, role ARN, ecr_key, ECR URL, handoff paths)"
  value = {
    for k, v in local.lambda_apps : k => {
      name                      = v.name
      aws_region                = v.aws_region
      primary_database          = v.primary_database
      roles                     = v.roles
      lambda_execution_role_arn = aws_iam_role.lambda_exec[k].arn
      ecr_key                   = v.ecr_key
      ecr_repository_url        = aws_ecr_repository.this[v.ecr_key].repository_url
      tfvars_path               = v.tfvars_path
      secret_name               = v.secret_name
      secret_arn                = try(aws_secretsmanager_secret.app[k].arn, null)
    }
  }
}

output "app_secret_arns" {
  description = "Map of lambda_apps key to Secrets Manager ARN (only apps with secret set)"
  value       = { for k, s in aws_secretsmanager_secret.app : k => s.arn }
}

output "app_secret_names" {
  description = "Map of lambda_apps key to Secrets Manager name (only apps with secret set)"
  value       = { for k, s in aws_secretsmanager_secret.app : k => s.name }
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
