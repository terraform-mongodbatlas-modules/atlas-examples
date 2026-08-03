output "vpc_id" {
  description = "ID of the VPC created for the E2E run"
  value       = aws_vpc.this.id
}

output "private_subnet_ids" {
  description = "IDs of the two private subnets (different AZs)"
  value       = aws_subnet.private[*].id
}
