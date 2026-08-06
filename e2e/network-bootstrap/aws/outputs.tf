output "vpc_id" {
  description = "ID of the VPC created for the E2E run"
  value       = aws_vpc.this.id
}

output "private_subnet_ids" {
  description = "IDs of the two private subnets (different AZs)"
  value       = aws_subnet.private[*].id
}

output "regions" {
  description = "Ready-to-consume value for the example's regions variable (name in Atlas region format)"
  value = [{
    name       = upper(replace(var.aws_region, "-", "_"))
    vpc_id     = aws_vpc.this.id
    subnet_ids = aws_subnet.private[*].id
  }]
}
