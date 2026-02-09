# ---------------------------------------------------------------------------
# Atlas Connectivity Validation VM Module (AWS)
# ---------------------------------------------------------------------------
# Creates an EC2 instance to validate MongoDB Atlas connectivity over PrivateLink.
#
# Features:
#   - Default: SSM Session Manager access (no public IP)
#   - Optional: SSH via EC2 Instance Connect Endpoint
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

  use_ssh = var.admin_ssh_public_key != null && trimspace(var.admin_ssh_public_key) != ""

  use_existing_instance_profile = var.ssm_instance_profile_name != null && trimspace(var.ssm_instance_profile_name) != ""
  create_instance_profile       = var.create_ssm_instance_profile && !local.use_existing_instance_profile

  # Supports both SRV and standard connection string formats:
  #   - SRV: mongodb+srv://[user:pass@]host/...
  #   - Standard: mongodb://[user:pass@]host1:port,host2:port,host3:port/?replicaSet=...
  is_srv_connection = can(regex("^mongodb\\+srv://", var.atlas_connection_string))

  connection_host = (
    can(regex("@([^/?]+)", var.atlas_connection_string))
    ? regex("@([^/?]+)", var.atlas_connection_string)[0]
    : regex("^mongodb(?:\\+srv)?://([^@/?]+)", var.atlas_connection_string)[0]
  )

  connection_string_with_creds = local.is_srv_connection ? (
    "mongodb+srv://${mongodbatlas_database_user.validation.username}:${random_password.db_user.result}@${local.connection_host}"
    ) : (
    "mongodb://${mongodbatlas_database_user.validation.username}:${random_password.db_user.result}@${local.connection_host}/?${regex("\\?(.+)$", var.atlas_connection_string)[0]}"
  )

  shared_scripts_path = "${path.module}/../../../shared/validation-vm"
  validate_script     = file("${local.shared_scripts_path}/validate-atlas.sh")

  cloud_init = templatefile("${local.shared_scripts_path}/cloud-init.yaml.tftpl", {
    admin_username    = local.admin_username
    validate_script   = local.validate_script
    connection_string = local.connection_string_with_creds
  })

  instance_profile_name = local.use_existing_instance_profile ? var.ssm_instance_profile_name : (
    local.create_instance_profile ? aws_iam_instance_profile.ssm[0].name : null
  )
}

# ---------------------------------------------------------------------------
# Data Sources
# ---------------------------------------------------------------------------
data "aws_vpc" "this" {
  id = var.vpc_id
}

data "aws_subnet" "private" {
  id = var.subnet_id
}

data "aws_subnet" "public" {
  count = var.create_nat_gateway && var.public_subnet_id != null ? 1 : 0
  id    = var.public_subnet_id
}

# Find the route table associated with the private subnet
data "aws_route_tables" "private" {
  vpc_id = var.vpc_id

  filter {
    name   = "association.subnet-id"
    values = [var.subnet_id]
  }
}

# Fallback to main route table if no explicit association
data "aws_route_table" "main" {
  vpc_id = var.vpc_id

  filter {
    name   = "association.main"
    values = ["true"]
  }
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
# Internet Gateway (optional - usually VPC already has one)
# ---------------------------------------------------------------------------
resource "aws_internet_gateway" "this" {
  count  = var.create_internet_gateway ? 1 : 0
  vpc_id = var.vpc_id
  tags   = merge(local.common_tags, { Name = "atlas-validation-igw" })
}

# ---------------------------------------------------------------------------
# NAT Gateway (optional - for private subnet internet access)
# ---------------------------------------------------------------------------
resource "aws_eip" "nat" {
  count  = var.create_nat_gateway ? 1 : 0
  domain = "vpc"
  tags   = merge(local.common_tags, { Name = "atlas-validation-nat-eip" })

  depends_on = [aws_internet_gateway.this]
}

resource "aws_nat_gateway" "this" {
  count         = var.create_nat_gateway ? 1 : 0
  allocation_id = aws_eip.nat[0].id
  subnet_id     = var.public_subnet_id

  tags = merge(local.common_tags, { Name = "atlas-validation-nat" })

  depends_on = [aws_internet_gateway.this]
}

# Add route to NAT Gateway in the private subnet's route table
resource "aws_route" "nat_gateway" {
  count = var.create_nat_gateway ? 1 : 0

  route_table_id         = coalesce(var.private_route_table_id, try(data.aws_route_tables.private.ids[0], data.aws_route_table.main.id))
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.this[0].id
}

# ---------------------------------------------------------------------------
# VPC Endpoints for SSM (optional - alternative to NAT for SSM access)
# ---------------------------------------------------------------------------
resource "aws_security_group" "vpc_endpoints" {
  count       = var.create_ssm_vpc_endpoints ? 1 : 0
  name        = "${local.instance_name}-vpc-endpoints-sg"
  description = "Security group for VPC endpoints"
  vpc_id      = var.vpc_id

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [data.aws_vpc.this.cidr_block]
    description = "HTTPS from VPC"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = local.common_tags
}

resource "aws_vpc_endpoint" "ssm" {
  count               = var.create_ssm_vpc_endpoints ? 1 : 0
  vpc_id              = var.vpc_id
  service_name        = "com.amazonaws.${data.aws_subnet.private.availability_zone_id != null ? regex("^[a-z]+-[a-z]+-[0-9]+", data.aws_subnet.private.availability_zone) : "us-east-1"}.ssm"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [var.subnet_id]
  security_group_ids  = [aws_security_group.vpc_endpoints[0].id]
  private_dns_enabled = true
  tags                = merge(local.common_tags, { Name = "atlas-validation-ssm-endpoint" })
}

resource "aws_vpc_endpoint" "ssmmessages" {
  count               = var.create_ssm_vpc_endpoints ? 1 : 0
  vpc_id              = var.vpc_id
  service_name        = "com.amazonaws.${data.aws_subnet.private.availability_zone_id != null ? regex("^[a-z]+-[a-z]+-[0-9]+", data.aws_subnet.private.availability_zone) : "us-east-1"}.ssmmessages"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [var.subnet_id]
  security_group_ids  = [aws_security_group.vpc_endpoints[0].id]
  private_dns_enabled = true
  tags                = merge(local.common_tags, { Name = "atlas-validation-ssmmessages-endpoint" })
}

resource "aws_vpc_endpoint" "ec2messages" {
  count               = var.create_ssm_vpc_endpoints ? 1 : 0
  vpc_id              = var.vpc_id
  service_name        = "com.amazonaws.${data.aws_subnet.private.availability_zone_id != null ? regex("^[a-z]+-[a-z]+-[0-9]+", data.aws_subnet.private.availability_zone) : "us-east-1"}.ec2messages"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [var.subnet_id]
  security_group_ids  = [aws_security_group.vpc_endpoints[0].id]
  private_dns_enabled = true
  tags                = merge(local.common_tags, { Name = "atlas-validation-ec2messages-endpoint" })
}

# ---------------------------------------------------------------------------
# EC2 Instance Connect Endpoint (optional - for SSH without bastion)
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
# SSM Instance Profile (optional)
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

  # SSH from CIDR (if SSH key provided)
  dynamic "ingress" {
    for_each = local.use_ssh && length(var.ssh_allowed_cidr_blocks) > 0 ? [1] : []
    content {
      from_port   = 22
      to_port     = 22
      protocol    = "tcp"
      cidr_blocks = var.ssh_allowed_cidr_blocks
      description = "SSH access (CIDR)"
    }
  }

  # SSH from Security Groups (if SSH key provided)
  dynamic "ingress" {
    for_each = local.use_ssh && length(var.ssh_source_security_group_ids) > 0 ? [1] : []
    content {
      from_port       = 22
      to_port         = 22
      protocol        = "tcp"
      security_groups = tolist(var.ssh_source_security_group_ids)
      description     = "SSH access (SG)"
    }
  }

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

  # SSH from VPC CIDR (fallback for EIC when endpoint already exists)
  dynamic "ingress" {
    for_each = !var.create_ec2_instance_connect_endpoint ? [1] : []
    content {
      from_port   = 22
      to_port     = 22
      protocol    = "tcp"
      cidr_blocks = [data.aws_vpc.this.cidr_block]
      description = "SSH from VPC (for existing EIC endpoints)"
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
# Key Pair (optional)
# ---------------------------------------------------------------------------
resource "aws_key_pair" "validation" {
  count      = local.use_ssh ? 1 : 0
  key_name   = "${local.instance_name}-key"
  public_key = var.admin_ssh_public_key
}

# ---------------------------------------------------------------------------
# EC2 Instance
# ---------------------------------------------------------------------------
resource "aws_instance" "validation" {
  ami           = data.aws_ami.ubuntu.id
  instance_type = var.instance_type
  subnet_id     = var.subnet_id

  vpc_security_group_ids = [aws_security_group.validation.id]
  key_name               = local.use_ssh ? aws_key_pair.validation[0].key_name : null
  iam_instance_profile   = local.instance_profile_name

  user_data_base64 = base64encode(local.cloud_init)

  tags = merge(local.common_tags, {
    "Name" = local.instance_name
  })

  # Wait for NAT Gateway route before starting (so cloud-init can reach internet)
  depends_on = [aws_route.nat_gateway]
}
