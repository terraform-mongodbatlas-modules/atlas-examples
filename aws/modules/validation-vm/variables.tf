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
# SSH Access Configuration
# ---------------------------------------------------------------------------
variable "admin_ssh_public_key" {
  description = <<-EOT
    SSH public key for VM access.

    When provided (non-empty): creates an EC2 key pair and enables SSH.
    When empty/null (default): rely on SSM Session Manager only.
  EOT
  type        = string
  default     = ""
}

variable "ssh_allowed_cidr_blocks" {
  description = "CIDR blocks allowed to SSH into the VM (only used when SSH key is provided)"
  type        = list(string)
  default     = []
}

variable "ssh_source_security_group_ids" {
  description = "Security group IDs allowed to SSH into the VM (only used when SSH key is provided)"
  type        = set(string)
  default     = []
}

# ---------------------------------------------------------------------------
# SSM Configuration
# ---------------------------------------------------------------------------
variable "create_ssm_instance_profile" {
  description = "Create an instance profile with AmazonSSMManagedInstanceCore"
  type        = bool
  default     = true
}

variable "ssm_instance_profile_name" {
  description = "Existing instance profile name to use for SSM (overrides create_ssm_instance_profile)"
  type        = string
  default     = null
}

# ---------------------------------------------------------------------------
# Network Infrastructure (Automated Setup)
# ---------------------------------------------------------------------------
variable "create_nat_gateway" {
  description = <<-EOT
    Create a NAT Gateway to provide internet access for the private subnet.
    Required for cloud-init to install packages (mongosh, etc.).

    Set to false if:
    - Your subnet already has NAT Gateway access
    - You're using VPC endpoints for package repos
    - You're using a public subnet

    Note: NAT Gateway incurs hourly costs (~$0.045/hr + data transfer).
  EOT
  type        = bool
  default     = true
}

variable "public_subnet_id" {
  description = <<-EOT
    Public subnet ID for NAT Gateway placement.
    Required when create_nat_gateway = true.

    The public subnet must:
    - Have a route to an Internet Gateway
    - Be in the same AZ as the validation VM subnet (recommended)
  EOT
  type        = string
  default     = null
}

variable "create_internet_gateway" {
  description = <<-EOT
    Create an Internet Gateway for the VPC.
    Set to false if your VPC already has an IGW attached.
  EOT
  type        = bool
  default     = false
}

variable "create_ssm_vpc_endpoints" {
  description = <<-EOT
    Create VPC endpoints for SSM (Systems Manager).
    This allows SSM Session Manager to work without internet access.

    Creates endpoints for: ssm, ssmmessages, ec2messages

    Note: VPC endpoints have hourly costs (~$0.01/hr per endpoint per AZ).
  EOT
  type        = bool
  default     = false
}

variable "create_ec2_instance_connect_endpoint" {
  description = <<-EOT
    Create an EC2 Instance Connect Endpoint for SSH access without bastion.
    Allows `aws ec2-instance-connect ssh` to private instances.

    Note: EIC Endpoints are free but limited to 1 per VPC.
  EOT
  type        = bool
  default     = true
}

variable "existing_eic_endpoint_sg_id" {
  description = <<-EOT
    Security group ID of an existing EC2 Instance Connect Endpoint.
    Use this when your VPC already has an EIC Endpoint (limit 1 per VPC)
    and create_ec2_instance_connect_endpoint is false.

    When provided, an ingress rule allowing SSH from this security group
    is added to the validation VM's security group.
  EOT
  type        = string
  default     = null
}

# ---------------------------------------------------------------------------
# Route Table Configuration
# ---------------------------------------------------------------------------
variable "private_route_table_id" {
  description = <<-EOT
    Route table ID for the private subnet.
    Used to add NAT Gateway route when create_nat_gateway = true.

    If not provided, the module will attempt to find the main route table
    or the route table associated with the subnet.
  EOT
  type        = string
  default     = null
}
