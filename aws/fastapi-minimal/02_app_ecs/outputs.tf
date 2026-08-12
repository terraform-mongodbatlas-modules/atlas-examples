locals {
  smoke_test_url = "http://${var.alb_dns_name}${var.health_check_path}"
}

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

output "target_group_arn" {
  description = "ALB target group ARN for this app"
  value       = aws_lb_target_group.this.arn
}

output "task_definition_arn" {
  description = "Active ECS task definition ARN"
  value       = aws_ecs_task_definition.this.arn
}

output "smoke_test_url" {
  description = "Direct ALB URL for smoke tests (same path as the target group health check)"
  value       = local.smoke_test_url
}

output "operations" {
  description = "Copy-paste commands for post-apply checks. Run from the fastapi-minimal example root."
  value = {
    smoke_test     = "curl -fsS '${local.smoke_test_url}'"
    health_check   = "just health-check"
    tail_logs      = "aws logs tail ${aws_cloudwatch_log_group.ecs.name} --follow --region ${var.aws_region}"
    target_health  = "aws elbv2 describe-target-health --target-group-arn ${aws_lb_target_group.this.arn} --region ${var.aws_region}"
    service_events = "aws ecs describe-services --cluster ${aws_ecs_cluster.this.name} --services ${aws_ecs_service.this.name} --region ${var.aws_region} --query 'services[0].events[0:5]'"
  }
}
