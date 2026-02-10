# Required variables
# ----------------------------------------------------
variable "aws_region" {
  description = "AWS region for the provider (must match the region of your VPC/subnets)"
  type        = string
  default     = "us-east-1"
}

variable "org_id" {
  description = "MongoDB Atlas Organization ID"
  type        = string
}

variable "project_name" {
  description = "Name for the Atlas project"
  type        = string
}

variable "cluster_name" {
  description = "Name for the Atlas cluster"
  type        = string
}

variable "regions" {
  description = <<-EOT
    Region configurations with AWS networking for PrivateLink.
    AWS region is inferred from Atlas region name (e.g. US_EAST_1 → us-east-1).

    Example:
      regions = [
        {
          name       = "US_EAST_1"
          vpc_id     = "vpc-abc123"
          subnet_ids = ["subnet-111", "subnet-222"]  # Private subnets for PrivateLink
        }
      ]
  EOT

  type = list(object({
    name       = string
    vpc_id     = string
    subnet_ids = list(string)
    node_count = optional(number)
  }))
}

# Optional variables
# ----------------------------------------------------
variable "tags" {
  description = "Tags applied to all Atlas resources"
  type        = map(string)
  default     = {}
}

variable "ip_access_list" {
  description = <<-EOT
    Optional IP access list entries for Atlas.
    By default, no public IP access is allowed (PrivateLink only).
    Private IP whitelisting is not necessary, shown for example purposes only.
  EOT

  type = list(object({
    source  = string
    comment = optional(string)
  }))

  default = []
}

# Validation VM
# ----------------------------------------------------
variable "enable_validation_vm" {
  description = "Deploy a validation VM to test Atlas deployment over PrivateLink"
  type        = bool
  default     = true
}

# Validation VM - Network Infrastructure
# ----------------------------------------------------
variable "validation_vm_public_subnet_id" {
  description = <<-EOT
    Public subnet ID for NAT Gateway placement.
    Provide this only if the VM's private subnet lacks internet access.

    When provided, a NAT Gateway is created so cloud-init can download
    packages (mongosh). Also set validation_vm_private_route_table_id.

    The public subnet must:
    - Be in the same VPC as the validation VM
    - Have a route to an Internet Gateway
    - Ideally be in the same AZ as the validation VM subnet
  EOT
  type        = string
  default     = null
}

variable "validation_vm_private_route_table_id" {
  description = <<-EOT
    Route table ID for the VM's private subnet.
    Required when validation_vm_public_subnet_id is provided (NAT Gateway
    route is added here).
  EOT
  type        = string
  default     = null
}

# Validation VM - Access Methods
# ----------------------------------------------------
variable "validation_vm_create_ec2_instance_connect_endpoint" {
  description = <<-EOT
    Create an EC2 Instance Connect Endpoint for SSH access to private instances.
    This allows `aws ec2-instance-connect ssh` without a bastion host.

    Set to true only if no EIC endpoint exists in the VPC (limit: 1 per VPC).
    Alternatively, use SSM Session Manager.
  EOT
  type        = bool
  default     = false
}
