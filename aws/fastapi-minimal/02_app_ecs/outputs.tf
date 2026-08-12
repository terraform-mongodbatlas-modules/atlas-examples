output "alb_dns_name" {
  description = "Internet-facing ALB DNS name for smoke tests (from 01_lz)"
  value       = var.alb_dns_name
}

output "ecs_cluster_name" {
  description = "ECS cluster name"
  value       = aws_ecs_cluster.this.name
}

output "ecs_service_name" {
  description = "ECS service name"
  value       = aws_ecs_service.this.name
}

output "image_uri" {
  description = "Full image URI including tag"
  value       = local.image_uri
}

output "ecs_log_group_name" {
  description = "CloudWatch log group name"
  value       = aws_cloudwatch_log_group.ecs.name
}
