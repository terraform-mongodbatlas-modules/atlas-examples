output "ecr_repository_url" {
  description = "ECR repository URL used by this stack"
  value       = var.ecr_repository_url
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
