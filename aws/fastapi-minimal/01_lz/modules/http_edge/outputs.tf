output "alb_arn" {
  value = aws_lb.this.arn
}

output "alb_dns_name" {
  value = aws_lb.this.dns_name
}

output "alb_security_group_id" {
  value = aws_security_group.alb.id
}

output "listener_arn" {
  value = var.acm_certificate_arn != null ? aws_lb_listener.https[0].arn : aws_lb_listener.http[0].arn
}
