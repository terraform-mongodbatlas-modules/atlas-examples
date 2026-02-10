# ---------------------------------------------------------------------------
# Required Variables
# ---------------------------------------------------------------------------
variable "vpc_id" {
  description = "VPC ID where the validation VM will be deployed"
  type        = string
}

variable "subnet_id" {
  description = "Subnet ID for the validation VM (private subnet recommended)"
  type        = string
}

variable "atlas_project_id" {
  description = "MongoDB Atlas Project ID. Used to create temporary database user."
  type        = string
}

variable "atlas_connection_string" {
  description = <<-EOT
    MongoDB Atlas private endpoint connection string. Supports both formats:

    - SRV format: mongodb+srv://<host> (with or without credentials)
    - Standard format: mongodb://<host1>:<port>,<host2>:<port>,<host3>:<port>/?replicaSet=...

    The validation scripts will enumerate all hosts (via SRV lookup or comma-split)
    and verify each resolves to a private IP address.
  EOT
  type        = string
}

# ---------------------------------------------------------------------------
# Instance Configuration
# ---------------------------------------------------------------------------
variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t3.micro"
}

variable "atlas_cluster_name" {
  description = "MongoDB Atlas cluster name. Required for backup validation via Atlas CLI."
  type        = string
  default     = ""
}

variable "tags" {
  description = "Tags applied to AWS resources"
  type        = map(string)
  default     = {}
}

# ---------------------------------------------------------------------------
# VM Access
# ---------------------------------------------------------------------------
# Primary:     EC2 Instance Connect Endpoint
# Alternative: SSM Session Manager (browser or CLI)
# ---------------------------------------------------------------------------
variable "create_ec2_instance_connect_endpoint" {
  description = <<-EOT
    Create an EC2 Instance Connect Endpoint for SSH access to private instances.
    This allows `aws ec2-instance-connect ssh` without a bastion host.

    Set to false if:
    - An EIC endpoint already exists in the VPC (limit: 1 per VPC)
    - You only need SSM Session Manager access

  EOT
  type        = bool
  default     = true
}

variable "instance_profile_name" {
  description = <<-EOT
    Existing IAM instance profile name with SSM permissions.
    When null (default), the module creates one with AmazonSSMManagedInstanceCore.
  EOT
  type        = string
  default     = null
}

# ---------------------------------------------------------------------------
# Network Infrastructure (for package installation)
# ---------------------------------------------------------------------------
variable "public_subnet_id" {
  description = <<-EOT
    Public subnet ID for NAT Gateway placement.

    Provide this when the private subnet lacks internet access. A NAT Gateway
    is created so cloud-init can download packages (mongosh, etc.).

    When null (default): No NAT Gateway is created. If the subnet already has
    internet access, leave this null. Otherwise run ~/install-mongosh.sh
    manually after deployment when network is available.

    The public subnet must:
    - Have a route to an Internet Gateway
    - Be in the same AZ as the validation VM subnet (recommended)

    When provided, also set private_route_table_id so the NAT route can be added.

  EOT
  type        = string
  default     = null
}

variable "private_route_table_id" {
  description = <<-EOT
    Route table ID for the private subnet.
    Required when public_subnet_id is provided (NAT Gateway route is added here).
  EOT
  type        = string
  default     = null
}
