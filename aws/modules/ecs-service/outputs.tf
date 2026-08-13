output "ecs_cluster_name" {
  description = "ECS cluster name (created by this module from the handoff name)."
  value       = aws_ecs_cluster.this.name
}

output "ecs_service_name" {
  description = "ECS service name."
  value       = aws_ecs_service.this.name
}

output "image_uri" {
  description = "Full image URI including tag."
  value       = local.image_uri
}

output "ecs_log_group_name" {
  description = "CloudWatch log group name."
  value       = aws_cloudwatch_log_group.ecs.name
}

output "target_group_arn" {
  description = "ALB target group ARN for this app."
  value       = aws_lb_target_group.this.arn
}

output "task_definition_arn" {
  description = "Active ECS task definition ARN."
  value       = aws_ecs_task_definition.this.arn
}

output "container_port" {
  description = "ALB target group and container port."
  value       = local.container_port
}

output "health_check_path" {
  description = "Target group health check path."
  value       = local.health_check_path
}

output "index_run" {
  description = "Region, cluster, and service for one-shot RunTask against this service."
  value = {
    aws_region = local.aws_region
    cluster    = aws_ecs_cluster.this.name
    service    = aws_ecs_service.this.name
  }
}
