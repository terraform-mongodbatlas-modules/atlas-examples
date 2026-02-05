# Atlas Validation VM Module (AWS)

This module creates an EC2 instance to validate MongoDB Atlas connectivity over AWS PrivateLink. It includes optional automation for common networking requirements.

## Features

- **Validation Script**: Pre-installed script to test DNS, connection, and CRUD operations
- **Multiple Access Methods**: SSM Session Manager, EC2 Instance Connect, or SSH
- **Network Automation**: Optional NAT Gateway, VPC Endpoints, and EIC Endpoint creation
- **Temporary Credentials**: Creates a temporary database user for validation

## Usage

### Basic Usage (Requires Existing NAT Gateway)

```hcl
module "validation_vm" {
  source = "../modules/validation-vm"

  vpc_id    = "vpc-xxx"
  subnet_id = "subnet-xxx"  # Private subnet with NAT access

  atlas_project_id        = "your-project-id"
  atlas_connection_string = "mongodb+srv://cluster0.xxx.mongodb.net"
  atlas_cluster_name      = "cluster0"

  # NAT Gateway already exists in subnet
  create_nat_gateway = false
}
```

### With NAT Gateway Creation

```hcl
module "validation_vm" {
  source = "../modules/validation-vm"

  vpc_id    = "vpc-xxx"
  subnet_id = "subnet-private-xxx"

  atlas_project_id        = "your-project-id"
  atlas_connection_string = "mongodb+srv://cluster0.xxx.mongodb.net"
  atlas_cluster_name      = "cluster0"

  # Create NAT Gateway for internet access
  create_nat_gateway = true
  public_subnet_id   = "subnet-public-xxx"  # Required
}
```

### With SSM VPC Endpoints (No Internet)

```hcl
module "validation_vm" {
  source = "../modules/validation-vm"

  vpc_id    = "vpc-xxx"
  subnet_id = "subnet-xxx"

  atlas_project_id        = "your-project-id"
  atlas_connection_string = "mongodb+srv://cluster0.xxx.mongodb.net"

  # No NAT Gateway - use VPC endpoints for SSM
  create_nat_gateway     = false
  create_ssm_vpc_endpoints = true
}
```

## Inputs

### Required

| Name | Description | Type |
|------|-------------|------|
| `vpc_id` | VPC ID where the VM will be deployed | `string` |
| `subnet_id` | Subnet ID for the VM (private subnet recommended) | `string` |
| `atlas_project_id` | MongoDB Atlas project ID | `string` |
| `atlas_connection_string` | Atlas connection string (SRV or standard format) | `string` |

### Network Infrastructure

| Name | Description | Type | Default |
|------|-------------|------|---------|
| `create_nat_gateway` | Create NAT Gateway for internet access | `bool` | `true` |
| `public_subnet_id` | Public subnet for NAT Gateway (required if `create_nat_gateway = true`) | `string` | `null` |
| `create_internet_gateway` | Create Internet Gateway (if VPC doesn't have one) | `bool` | `false` |
| `private_route_table_id` | Route table for NAT Gateway route | `string` | auto-detected |
| `create_ssm_vpc_endpoints` | Create VPC endpoints for SSM | `bool` | `false` |
| `create_ec2_instance_connect_endpoint` | Create EIC endpoint for SSH | `bool` | `true` |

### Instance Configuration

| Name | Description | Type | Default |
|------|-------------|------|---------|
| `instance_type` | EC2 instance type | `string` | `t3.micro` |
| `admin_ssh_public_key` | SSH public key for key-based access | `string` | `""` |
| `atlas_cluster_name` | Cluster name for Atlas CLI operations | `string` | `""` |
| `tags` | Tags for AWS resources | `map(string)` | `{}` |

## Outputs

| Name | Description |
|------|-------------|
| `instance_id` | EC2 instance ID |
| `private_ip` | Private IP address |
| `admin_username` | Username for login (`ubuntu`) |
| `ssh_command` | Full SSH command via EC2 Instance Connect |
| `ssm_command` | Full SSM Session Manager command |
| `nat_gateway_id` | NAT Gateway ID (if created) |
| `eic_endpoint_id` | EC2 Instance Connect Endpoint ID (if created) |

## What Gets Created

### Always Created

- EC2 instance (Ubuntu 22.04)
- Security group with SSH and egress rules
- IAM role and instance profile for SSM
- Temporary Atlas database user

### Conditionally Created

| Resource | Condition | Cost |
|----------|-----------|------|
| NAT Gateway + EIP | `create_nat_gateway = true` | ~$0.045/hr |
| Internet Gateway | `create_internet_gateway = true` | Free |
| NAT Gateway route | `create_nat_gateway = true` | Free |
| VPC Endpoints (3) | `create_ssm_vpc_endpoints = true` | ~$0.03/hr |
| EC2 Instance Connect Endpoint | `create_ec2_instance_connect_endpoint = true` | Free |
| EC2 Key Pair | `admin_ssh_public_key != ""` | Free |

## Accessing the VM

### EC2 Instance Connect (Recommended)

```bash
aws ec2-instance-connect ssh \
  --instance-id <instance-id> \
  --os-user ubuntu
```

### SSM Session Manager

```bash
aws ssm start-session --target <instance-id>
```

**Note:** Requires NAT Gateway or SSM VPC Endpoints.

### SSH with Key

```bash
ssh -i ~/.ssh/your-key ubuntu@<private-ip>
```

**Note:** Requires network path to private IP (VPN, bastion, etc.)

## Validation Script

The VM includes `~/validate-atlas` which tests:

1. **DNS Resolution**: Verifies PrivateLink endpoints resolve to private IPs
2. **MongoDB Connection**: Tests connectivity with 10s timeout
3. **CRUD Operations**: Insert, read, delete test document

```bash
./validate-atlas
```

### Manual mongosh Installation

If cloud-init failed (no internet), install mongosh manually:

```bash
./install-mongosh.sh
```

## Network Requirements

### For Internet Access (Package Installation)

Either:
- Private subnet with route to NAT Gateway
- Direct internet access (public subnet)
- NAT Gateway created by this module (`create_nat_gateway = true`)

### For SSM Access

Either:
- Internet access (NAT Gateway or public subnet)
- SSM VPC Endpoints (`create_ssm_vpc_endpoints = true`)

### For EC2 Instance Connect

Either:
- EIC Endpoint created by this module (`create_ec2_instance_connect_endpoint = true`)
- Existing EIC Endpoint in the VPC
- Direct network path + SSH key

## Troubleshooting

### mongosh: command not found

```bash
./install-mongosh.sh
```

### Permission denied: ~/.mongodb

```bash
sudo chown -R ubuntu:ubuntu ~/.mongodb
```

### Connection timeout

Check Private Hosted Zone and security groups:

```bash
# Test DNS
dig +short cluster0.xxx.mongodb.net

# Should return private IPs (10.x.x.x, 172.16-31.x.x, 192.168.x.x)
```

### SSM TargetNotConnected

The instance can't reach SSM endpoints. Either:
- Add NAT Gateway route to the private subnet
- Create SSM VPC Endpoints

### cloud-init failed

View logs:

```bash
sudo cat /var/log/cloud-init-output.log
cloud-init status --long
```
