# ---------------------------------------------------------------------------
# Atlas Connectivity Validation VM Module (AWS)
# ---------------------------------------------------------------------------
# Creates an EC2 instance to validate MongoDB Atlas connectivity over PrivateLink.
#
# Features:
#   - Primary access: EC2 Instance Connect Endpoint
#   - Alternative access: SSM Session Manager (browser or CLI)
#   - Optional: NAT Gateway for private subnet internet access
#   - Pre-installed mongosh, Atlas CLI, and validation scripts
#   - Validates DNS resolution, connectivity, and CRUD operations
# ---------------------------------------------------------------------------

locals {
  instance_name  = "atlas-validation-vm"
  admin_username = "ubuntu"
  db_username    = "atlas-validation-user"

  common_tags = merge(var.tags, {
    "Purpose"   = "Atlas Connectivity Validation"
    "ManagedBy" = "Terraform"
  })

  create_instance_profile = var.instance_profile_name == null

  # NAT Gateway is created when public_subnet_id is provided (signals the private
  # subnet lacks internet access and needs a NAT for cloud-init package downloads).
  create_nat_gateway = var.public_subnet_id != null

  # Supports both SRV and standard connection string formats:
  #   - SRV: mongodb+srv://[user:pass@]host/...
  #   - Standard: mongodb://[user:pass@]host1:port,host2:port,host3:port/?replicaSet=...
  is_srv_connection = can(regex("^mongodb\\+srv://", var.atlas_connection_string))

  connection_host = (
    can(regex("@([^/?]+)", var.atlas_connection_string))
    ? regex("@([^/?]+)", var.atlas_connection_string)[0]
    : regex("^mongodb(?:\\+srv)?://([^@/?]+)", var.atlas_connection_string)[0]
  )

  # Extract query parameters from a standard connection string (if present).
  # e.g. "mongodb://host:port/?replicaSet=rs0&ssl=true" → "replicaSet=rs0&ssl=true"
  connection_query_params = (
    !local.is_srv_connection && can(regex("\\?(.+)$", var.atlas_connection_string))
    ? regex("\\?(.+)$", var.atlas_connection_string)[0]
    : ""
  )

  connection_string_with_creds = local.is_srv_connection ? (
    "mongodb+srv://${mongodbatlas_database_user.validation.username}:${random_password.db_user.result}@${local.connection_host}"
    ) : (
    "mongodb://${mongodbatlas_database_user.validation.username}:${random_password.db_user.result}@${local.connection_host}/${local.connection_query_params != "" ? "?${local.connection_query_params}" : ""}"
  )

  shared_scripts_path = "${path.module}/../../../shared/validation-vm"
  validate_script     = file("${local.shared_scripts_path}/validate-atlas.sh")

  cloud_init = templatefile("${local.shared_scripts_path}/cloud-init.yaml.tftpl", {
    admin_username    = local.admin_username
    validate_script   = local.validate_script
    connection_string = local.connection_string_with_creds
  })
}

data "aws_vpc" "this" {
  id = var.vpc_id
}

data "aws_subnet" "private" {
  id = var.subnet_id
}

resource "random_password" "db_user" {
  length  = 24
  special = false
}

# Temporary Database User (for SCRAM authentication)
resource "mongodbatlas_database_user" "validation" {
  project_id         = var.atlas_project_id
  username           = local.db_username
  password           = random_password.db_user.result
  auth_database_name = "admin"

  roles {
    role_name     = "readWriteAnyDatabase"
    database_name = "admin"
  }

  labels {
    key   = "purpose"
    value = "validation-vm-temporary"
  }
}

# ---------------------------------------------------------------------------
# AMI (Ubuntu 22.04 LTS)
# ---------------------------------------------------------------------------
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# ---------------------------------------------------------------------------
# NAT Gateway (optional - for private subnet internet access)
# ---------------------------------------------------------------------------
# Created only when the private subnet lacks a 0.0.0.0/0 route AND
# public_subnet_id is provided. The public subnet must already have
# a route to an Internet Gateway (standard AWS "public subnet" requirement).
# ---------------------------------------------------------------------------
resource "aws_eip" "nat" {
  count  = local.create_nat_gateway ? 1 : 0
  domain = "vpc"
  tags   = merge(local.common_tags, { Name = "atlas-validation-nat-eip" })
}

resource "aws_nat_gateway" "this" {
  count         = local.create_nat_gateway ? 1 : 0
  allocation_id = aws_eip.nat[0].id
  subnet_id     = var.public_subnet_id

  tags = merge(local.common_tags, { Name = "atlas-validation-nat" })
}

# Add route to NAT Gateway in the private subnet's route table
resource "aws_route" "nat_gateway" {
  count = local.create_nat_gateway ? 1 : 0

  route_table_id         = var.private_route_table_id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.this[0].id
}

# ---------------------------------------------------------------------------
# EC2 Instance Connect Endpoint
# ---------------------------------------------------------------------------
resource "aws_security_group" "eic_endpoint" {
  count       = var.create_ec2_instance_connect_endpoint ? 1 : 0
  name        = "${local.instance_name}-eic-endpoint-sg"
  description = "Security group for EC2 Instance Connect Endpoint"
  vpc_id      = var.vpc_id

  egress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [data.aws_vpc.this.cidr_block]
    description = "SSH to VPC instances"
  }

  tags = local.common_tags
}

resource "aws_ec2_instance_connect_endpoint" "this" {
  count              = var.create_ec2_instance_connect_endpoint ? 1 : 0
  subnet_id          = var.subnet_id
  security_group_ids = [aws_security_group.eic_endpoint[0].id]
  preserve_client_ip = false

  tags = merge(local.common_tags, { Name = "atlas-validation-eic-endpoint" })
}

# ---------------------------------------------------------------------------
# SSM Instance Profile
# ---------------------------------------------------------------------------
resource "aws_iam_role" "ssm" {
  count = local.create_instance_profile ? 1 : 0

  name = "${local.instance_name}-ssm-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ssm_core" {
  count      = local.create_instance_profile ? 1 : 0
  role       = aws_iam_role.ssm[0].name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "ssm" {
  count = local.create_instance_profile ? 1 : 0

  name = "${local.instance_name}-ssm-profile"
  role = aws_iam_role.ssm[0].name
}

# ---------------------------------------------------------------------------
# Security Group
# ---------------------------------------------------------------------------
resource "aws_security_group" "validation" {
  name        = "${local.instance_name}-sg"
  description = "Security group for Atlas validation VM"
  vpc_id      = var.vpc_id

  # SSH from EC2 Instance Connect Endpoint
  dynamic "ingress" {
    for_each = var.create_ec2_instance_connect_endpoint ? [1] : []
    content {
      from_port       = 22
      to_port         = 22
      protocol        = "tcp"
      security_groups = [aws_security_group.eic_endpoint[0].id]
      description     = "SSH from EC2 Instance Connect Endpoint"
    }
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = local.common_tags
}

# ---------------------------------------------------------------------------
# EC2 Instance
# ---------------------------------------------------------------------------
resource "aws_instance" "validation" {
  ami           = data.aws_ami.ubuntu.id
  instance_type = var.instance_type
  subnet_id     = var.subnet_id

  vpc_security_group_ids = [aws_security_group.validation.id]
  iam_instance_profile   = local.create_instance_profile ? aws_iam_instance_profile.ssm[0].name : var.instance_profile_name

  user_data_base64 = base64encode(local.cloud_init)

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  tags = merge(local.common_tags, {
    "Name" = local.instance_name
  })

  # Wait for NAT Gateway route before starting (so cloud-init can reach internet)
  depends_on = [aws_route.nat_gateway]
}
