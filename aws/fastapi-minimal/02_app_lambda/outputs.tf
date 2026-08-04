output "ecr_repository_url" {
  description = "ECR repository URL (created or BYO)"
  value       = local.ecr_repository_url
}

output "image_uri" {
  description = "Full image URI including tag"
  value       = local.image_uri
}

output "lambda_function_name" {
  description = "Lambda function name"
  value       = aws_lambda_function.app.function_name
}

output "function_url" {
  description = "Lambda Function URL for smoke tests"
  value       = aws_lambda_function_url.app.function_url
}

output "lambda_log_group_name" {
  description = "CloudWatch log group name"
  value       = aws_cloudwatch_log_group.lambda.name
}

output "ecr_managed" {
  description = "True when this stack created the ECR repository"
  value       = local.create_ecr
}
