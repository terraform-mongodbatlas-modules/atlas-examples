# ---------------------------------------------------------------------------
# Instance Outputs
# ---------------------------------------------------------------------------
output "instance_id" {
  description = "EC2 instance ID"
  value       = aws_instance.validation.id
}

output "private_ip" {
  description = "Private IP address of the validation VM"
  value       = aws_instance.validation.private_ip
}

output "admin_username" {
  description = "Username for VM login"
  value       = local.admin_username
}

output "access" {
  description = "How to access the VM"
  value       = local.use_ssh ? "SSH (key-based) or SSM Session Manager" : "SSM Session Manager or EC2 Instance Connect"
}

# ---------------------------------------------------------------------------
# Access Commands
# ---------------------------------------------------------------------------
output "ssh_command" {
  description = "Command to SSH into the VM via EC2 Instance Connect"
  value       = "aws ec2-instance-connect ssh --instance-id ${aws_instance.validation.id} --os-user ${local.admin_username}"
}

output "ssm_command" {
  description = "Command to connect via SSM Session Manager"
  value       = "aws ssm start-session --target ${aws_instance.validation.id}"
}

output "validation_command" {
  description = "Command to run validation script on the VM"
  value       = "./validate-atlas"
}

# ---------------------------------------------------------------------------
# Networking Outputs
# ---------------------------------------------------------------------------
output "nat_gateway_id" {
  description = "NAT Gateway ID (if created)"
  value       = var.create_nat_gateway ? aws_nat_gateway.this[0].id : null
}

output "nat_gateway_public_ip" {
  description = "NAT Gateway public IP (if created)"
  value       = var.create_nat_gateway ? aws_eip.nat[0].public_ip : null
}

output "eic_endpoint_id" {
  description = "EC2 Instance Connect Endpoint ID (if created)"
  value       = var.create_ec2_instance_connect_endpoint ? aws_ec2_instance_connect_endpoint.this[0].id : null
}

output "ssm_vpc_endpoints" {
  description = "SSM VPC Endpoint IDs (if created)"
  value = var.create_ssm_vpc_endpoints ? {
    ssm         = aws_vpc_endpoint.ssm[0].id
    ssmmessages = aws_vpc_endpoint.ssmmessages[0].id
    ec2messages = aws_vpc_endpoint.ec2messages[0].id
  } : null
}

# ---------------------------------------------------------------------------
# Security Group Outputs
# ---------------------------------------------------------------------------
output "security_group_id" {
  description = "Security group ID of the validation VM"
  value       = aws_security_group.validation.id
}

output "eic_endpoint_security_group_id" {
  description = "Security group ID of the EC2 Instance Connect Endpoint (if created)"
  value       = var.create_ec2_instance_connect_endpoint ? aws_security_group.eic_endpoint[0].id : null
}
