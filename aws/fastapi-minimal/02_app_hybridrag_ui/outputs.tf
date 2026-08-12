output "alb_dns_name" {
  description = "Internet-facing ALB DNS name for smoke tests (from 01_lz)"
  value       = module.ecs.alb_dns_name
}

output "ecs_cluster_name" {
  description = "ECS cluster name"
  value       = module.ecs.ecs_cluster_name
}

output "ecs_service_name" {
  description = "ECS service name"
  value       = module.ecs.ecs_service_name
}

output "image_uri" {
  description = "Full image URI including tag"
  value       = module.ecs.image_uri
}

output "ecs_log_group_name" {
  description = "CloudWatch log group name"
  value       = module.ecs.ecs_log_group_name
}

output "target_group_arn" {
  description = "ALB target group ARN for this app"
  value       = module.ecs.target_group_arn
}

output "task_definition_arn" {
  description = "Active ECS task definition ARN"
  value       = module.ecs.task_definition_arn
}

output "smoke_test_url" {
  description = "Direct ALB URL for smoke tests"
  value       = module.ecs.smoke_test_url
}

output "task_cpu" {
  description = "Fargate task CPU units"
  value       = module.ecs.task_cpu
}

output "task_memory" {
  description = "Fargate task memory (MiB)"
  value       = module.ecs.task_memory
}

output "container_port" {
  description = "ALB target group and container port"
  value       = module.ecs.container_port
}

output "operations" {
  description = "Copy-paste commands for post-apply checks"
  value       = module.ecs.operations
}
