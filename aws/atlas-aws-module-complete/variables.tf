# Required variables
# ----------------------------------------------------
variable "atlas_org_id" {
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

    Example:
      regions = [
        {
          name       = "US_EAST_1"
          aws_region = "us-east-1"
          vpc_id     = "vpc-abc123"
          subnet_ids = ["subnet-111", "subnet-222"]  # Private subnets for PrivateLink
        }
      ]
  EOT

  type = list(object({
    name       = string
    aws_region = string
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

# PrivateLink security group (applied to all endpoints)
variable "privatelink_security_group" {
  description = "Security group configuration for AWS PrivateLink endpoints"
  type = object({
    ids                 = optional(list(string))
    create              = optional(bool, true)
    name_prefix         = optional(string, "atlas-privatelink-")
    inbound_cidr_blocks = optional(list(string))
    inbound_source_sgs  = optional(set(string), [])
    from_port           = optional(number, 1024)
    to_port             = optional(number, 65535)
  })
  default = {}
}

# Backup Export (S3)
# ----------------------------------------------------
variable "backup_export_enabled" {
  description = "Enable backup export to S3"
  type        = bool
  default     = true
}

variable "backup_bucket_name" {
  description = "Existing S3 bucket name for backup export (if null, module can create one)"
  type        = string
  default     = null
}

# Validation VM
# ----------------------------------------------------
variable "enable_validation_vm" {
  description = "Deploy a validation VM to test Atlas deployment over PrivateLink"
  type        = bool
  default     = true
}

variable "validation_vm_instance_type" {
  description = "EC2 instance type for validation VM"
  type        = string
  default     = "t3.micro"
}

variable "validation_vm_ssh_public_key" {
  description = "SSH public key for validation VM access (optional; use SSM by default)"
  type        = string
  default     = ""
}

variable "validation_vm_subnet_id" {
  description = "Private subnet ID for the validation VM (defaults to first region's first subnet)"
  type        = string
  default     = null
}

variable "validation_vm_vpc_id" {
  description = "VPC ID for the validation VM (defaults to first region VPC)"
  type        = string
  default     = null
}

# Validation VM - Network Infrastructure
# ----------------------------------------------------
variable "validation_vm_create_nat_gateway" {
  description = <<-EOT
    Create a NAT Gateway for the validation VM's private subnet.
    Required for cloud-init to download and install packages (mongosh).

    Set to false if:
    - Your private subnet already has NAT Gateway access
    - You want to install mongosh manually after deployment

    Note: NAT Gateway costs ~$0.045/hr + data transfer fees.
  EOT
  type        = bool
  default     = true
}

variable "validation_vm_public_subnet_id" {
  description = <<-EOT
    Public subnet ID for NAT Gateway placement.
    Required when validation_vm_create_nat_gateway = true.

    The public subnet must:
    - Be in the same VPC as the validation VM
    - Have a route to an Internet Gateway
    - Ideally be in the same AZ as the validation VM subnet
  EOT
  type        = string
  default     = null
}

variable "validation_vm_create_internet_gateway" {
  description = <<-EOT
    Create an Internet Gateway for the VPC.
    Set to false (default) if your VPC already has an IGW attached.
  EOT
  type        = bool
  default     = false
}

variable "validation_vm_private_route_table_id" {
  description = <<-EOT
    Route table ID for the validation VM's private subnet.
    Used to add NAT Gateway route. If not provided, the module will
    attempt to find the route table associated with the subnet.
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

    Set to false if:
    - An EIC endpoint already exists in the subnet (limit: 1 per VPC)
    - You only need SSM Session Manager access

    Note: EIC Endpoints are free but limited to 1 per VPC.
  EOT
  type        = bool
  default     = true
}

variable "validation_vm_create_ssm_vpc_endpoints" {
  description = <<-EOT
    Create VPC endpoints for SSM Session Manager.
    This allows SSM access without NAT Gateway (reduces costs).

    Creates endpoints for: ssm, ssmmessages, ec2messages

    Note: VPC endpoints cost ~$0.01/hr per endpoint per AZ.
  EOT
  type        = bool
  default     = false
}
