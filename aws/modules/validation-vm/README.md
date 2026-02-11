# Atlas Validation VM Module (AWS)

This module creates an EC2 instance to validate MongoDB Atlas connectivity over AWS PrivateLink. It includes optional automation for common networking requirements.

## Features

- **Validation Script**: Pre-installed script to test DNS, connection, and CRUD operations
- **Primary Access**: EC2 Instance Connect Endpoint (SSH without bastion)
- **Alternative Access**: SSM Session Manager (browser or CLI)
- **Optional NAT Gateway**: For private subnets without internet access
- **Temporary Credentials**: Creates a temporary database user for validation

## Usage

### Basic Usage (Subnet Already Has Internet Access)

```hcl
module "validation_vm" {
  source = "../modules/validation-vm"

  vpc_id    = "vpc-xxx"
  subnet_id = "subnet-xxx"  # Private subnet with existing NAT/internet access

  atlas_project_id        = "your-project-id"
  atlas_connection_string = "mongodb+srv://cluster0.xxx.mongodb.net"
  atlas_cluster_name      = "cluster0"
}
```

### With NAT Gateway and EC2 Instance Connect

```hcl
module "validation_vm" {
  source = "../modules/validation-vm"

  vpc_id    = "vpc-xxx"
  subnet_id = "subnet-private-xxx"

  atlas_project_id        = "your-project-id"
  atlas_connection_string = "mongodb+srv://cluster0.xxx.mongodb.net"
  atlas_cluster_name      = "cluster0"

  # Create NAT Gateway (private subnet lacks internet access)
  public_subnet_id       = "subnet-public-xxx"
  private_route_table_id = "rtb-xxx"

  # Create EC2 Instance Connect Endpoint for SSH access
  create_ec2_instance_connect_endpoint = true
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
| `public_subnet_id` | Public subnet for NAT Gateway (triggers NAT creation) | `string` | `null` |
| `private_route_table_id` | Route table for NAT Gateway route (required with `public_subnet_id`) | `string` | `null` |

### VM Access

| Name | Description | Type | Default |
|------|-------------|------|---------|
| `create_ec2_instance_connect_endpoint` | Create EIC endpoint for SSH | `bool` | `false` |
| `instance_profile_name` | Existing IAM instance profile with SSM permissions | `string` | `null` (auto-created) |

### Instance Configuration

| Name | Description | Type | Default |
|------|-------------|------|---------|
| `instance_type` | EC2 instance type | `string` | `t3.micro` |
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
| `ssm_validation_command` | Full SSM command to run validation as the admin user |
| `validation_command` | Command to run the validation script on the VM |
| `nat_gateway_id` | NAT Gateway ID (if created) |
| `nat_gateway_public_ip` | NAT Gateway public IP (if created) |
| `eic_endpoint_id` | EC2 Instance Connect Endpoint ID (if created) |
| `security_group_id` | Security group ID of the validation VM |
| `eic_endpoint_security_group_id` | Security group ID of the EIC endpoint (if created) |

## What Gets Created

### Always Created

- EC2 instance (Ubuntu 22.04) with IMDSv2 enforced
- Security group (egress-only; SSH ingress added only when EIC endpoint is created)
- Temporary Atlas database user (SCRAM, `readWriteAnyDatabase`)

### Conditionally Created

| Resource | Condition | Cost |
|----------|-----------|------|
| IAM role + instance profile (SSM) | `instance_profile_name` is `null` (default) | Free |
| NAT Gateway + EIP | `public_subnet_id` provided | ~$0.045/hr |
| NAT Gateway route (0.0.0.0/0) | `public_subnet_id` provided | Free |
| EC2 Instance Connect Endpoint + SG | `create_ec2_instance_connect_endpoint = true` | Free |

## Accessing the VM

### EC2 Instance Connect (Primary)

Requires `create_ec2_instance_connect_endpoint = true` (or an existing EIC endpoint in the VPC).

```bash
aws ec2-instance-connect ssh \
  --instance-id <instance-id> \
  --os-user ubuntu
```

### SSM Session Manager (Alternative)

Always available (IAM instance profile with SSM permissions is attached by default).

```bash
# Interactive shell (starts as ssm-user)
aws ssm start-session --target <instance-id>

# Run validation directly as the admin user
aws ssm start-session --target <instance-id> \
  --document-name AWS-StartInteractiveCommand \
  --parameters command='sudo su - ubuntu -c ./validate-atlas'
```

**Note:** Requires NAT Gateway or existing internet access for SSM agent connectivity.

## Validation Script

The VM includes `~/validate-atlas` which tests:

1. **DNS Resolution**: Verifies PrivateLink endpoints resolve to private IPs
2. **MongoDB Connection**: Tests connectivity with 10s timeout
3. **CRUD Operations**: Insert, read, delete test document

```bash
./validate-atlas
```

### Manual mongosh Installation

If cloud-init failed (no internet), install mongosh manually once the subnet has outbound access:

```bash
~/install-mongosh.sh
```

## Troubleshooting

### mongosh: command not found

Cloud-init likely failed to download packages. Run the installer manually:

```bash
~/install-mongosh.sh
```

### Connection timeout

Check PrivateLink DNS resolution and security groups:

```bash
# Test DNS - should return private IPs (10.x.x.x, 172.16-31.x.x, 192.168.x.x)
dig +short cluster0.xxx.mongodb.net
```

### SSM TargetNotConnected

The instance can't reach SSM endpoints. Ensure the subnet has internet access (NAT Gateway or direct route).

### cloud-init failed

View logs:

```bash
sudo cat /var/log/cloud-init-output.log
cloud-init status --long
```
