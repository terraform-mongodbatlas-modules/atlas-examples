# MongoDB Atlas AWS Landing Zone Example

This example deploys a complete MongoDB Atlas environment integrated with AWS, including:

- **Atlas Project & Cluster** with multi-region support
- **AWS PrivateLink** endpoints for secure, private connectivity
- **AWS KMS** encryption at rest
- **S3 Backup Export** for disaster recovery
- **Validation VM** to test PrivateLink connectivity

## Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              MongoDB Atlas                                   │
│  ┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐          │
│  │  Atlas Project  │───▶│  Atlas Cluster  │◀───│  Cloud Provider │          │
│  │                 │    │  (Multi-Region) │    │  Access (IAM)   │          │
│  └─────────────────┘    └────────┬────────┘    └─────────────────┘          │
│                                  │                                           │
│                    ┌─────────────┴─────────────┐                            │
│                    ▼                           ▼                            │
│           ┌────────────────┐          ┌────────────────┐                    │
│           │ PrivateLink    │          │ PrivateLink    │                    │
│           │ Service        │          │ Service        │                    │
│           │ (us-east-1)    │          │ (us-west-2)    │                    │
│           └───────┬────────┘          └───────┬────────┘                    │
└───────────────────┼───────────────────────────┼─────────────────────────────┘
                    │                           │
┌───────────────────┼───────────────────────────┼─────────────────────────────┐
│                   │        AWS Account        │                             │
│   ┌───────────────┼───────────────────────────┼───────────────────────┐     │
│   │               │      VPC (us-east-1)      │                       │     │
│   │   ┌───────────▼────────────┐              │                       │     │
│   │   │  VPC Endpoint          │              │   ┌─────────────────┐ │     │
│   │   │  (PrivateLink)         │              │   │  NAT Gateway    │ │     │
│   │   └───────────┬────────────┘              │   │  (optional)     │ │     │
│   │               │                           │   └────────┬────────┘ │     │
│   │   ┌───────────┼───────────────────────────┼────────────┼────────┐ │     │
│   │   │           │    Private Subnet         │            │        │ │     │
│   │   │   ┌───────▼────────┐    ┌─────────────▼──────┐     │        │ │     │
│   │   │   │ Validation VM  │───▶│  Internet Access   │─────┘        │ │     │
│   │   │   │ (mongosh)      │    │  (for cloud-init)  │              │ │     │
│   │   │   └────────────────┘    └────────────────────┘              │ │     │
│   │   └─────────────────────────────────────────────────────────────┘ │     │
│   └───────────────────────────────────────────────────────────────────┘     │
│                                                                             │
│   ┌─────────────────┐    ┌─────────────────┐                               │
│   │  KMS Key        │    │  S3 Bucket      │                               │
│   │  (Encryption)   │    │  (Backups)      │                               │
│   └─────────────────┘    └─────────────────┘                               │
└─────────────────────────────────────────────────────────────────────────────┘
```

## Prerequisites

### 1. MongoDB Atlas

- Atlas Organization with Programmatic API Keys
- API keys with Organization Owner or Project Owner permissions

```bash
# Set Atlas credentials
export MONGODB_ATLAS_PUBLIC_API_KEY="your-public-key"
export MONGODB_ATLAS_PRIVATE_API_KEY="your-private-key"
```

### 2. AWS Account

- VPC with **DNS hostnames** and **DNS resolution** enabled
- **Private subnets** (at least 2 in different AZs for HA)
- **Public subnet** (required if creating NAT Gateway for validation VM)
- **Private Hosted Zone** for `*.mongodb.net` associated with your VPC

```bash
# Set AWS credentials (choose one method)
export AWS_PROFILE="your-profile"
# OR
export AWS_ACCESS_KEY_ID="your-key"
export AWS_SECRET_ACCESS_KEY="your-secret"
```

### 3. Required IAM Permissions

The AWS credentials need permissions for:

- EC2 (VPC endpoints, security groups, instances)
- IAM (roles, policies, instance profiles)
- KMS (key creation, grants)
- S3 (bucket creation, policies)
- Route53 (private hosted zones - if not pre-created)

## Quick Start

### 1. Configure Variables

```bash
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your values
```

### 2. Deploy

```bash
terraform init
terraform plan
terraform apply
```

### 3. Validate Connectivity

```bash
# Get the SSH command from outputs
terraform output -json validation_vm | jq -r '.ssh_command'

# Connect to the validation VM
aws ec2-instance-connect ssh --instance-id <instance-id> --os-user ubuntu

# Run validation script
./validate-atlas
```

## Configuration Options

### Minimal Configuration

```hcl
atlas_org_id = "your-org-id"
project_name = "my-project"
cluster_name = "my-cluster"

regions = [{
  name       = "US_EAST_1"
  aws_region = "us-east-1"
  vpc_id     = "vpc-xxx"
  subnet_ids = ["subnet-aaa", "subnet-bbb"]
}]

# Required for validation VM internet access
validation_vm_public_subnet_id = "subnet-public-xxx"
```

### Multi-Region Configuration

```hcl
regions = [
  {
    name       = "US_EAST_1"
    aws_region = "us-east-1"
    vpc_id     = "vpc-east"
    subnet_ids = ["subnet-east-1", "subnet-east-2"]
  },
  {
    name       = "US_WEST_2"
    aws_region = "us-west-2"
    vpc_id     = "vpc-west"
    subnet_ids = ["subnet-west-1", "subnet-west-2"]
  }
]
```

### Validation VM Options

The validation VM needs **internet access** during cloud-init to install `mongosh`. Several options are available:

#### Option A: NAT Gateway (Default)

Creates a NAT Gateway for the private subnet. **Recommended for most cases.**

```hcl
validation_vm_create_nat_gateway = true
validation_vm_public_subnet_id   = "subnet-public-xxx"  # Required
```

**Cost:** ~$0.045/hr + data transfer

#### Option B: Existing NAT Gateway

If your subnet already has NAT Gateway access:

```hcl
validation_vm_create_nat_gateway = false
```

#### Option C: SSM VPC Endpoints (No Internet)

Creates VPC endpoints for SSM access. `mongosh` won't be pre-installed.

```hcl
validation_vm_create_nat_gateway     = false
validation_vm_create_ssm_vpc_endpoints = true
```

**Cost:** ~$0.01/hr per endpoint per AZ (3 endpoints = ~$0.03/hr)

After connecting via SSM, install mongosh manually:
```bash
./install-mongosh.sh
```

## Accessing the Validation VM

### Method 1: EC2 Instance Connect (Recommended)

```bash
# Get instance ID
INSTANCE_ID=$(terraform output -json validation_vm | jq -r '.instance_id')

# SSH via EC2 Instance Connect
aws ec2-instance-connect ssh --instance-id $INSTANCE_ID --os-user ubuntu
```

### Method 2: SSM Session Manager

```bash
INSTANCE_ID=$(terraform output -json validation_vm | jq -r '.instance_id')
aws ssm start-session --target $INSTANCE_ID
```

**Note:** SSM requires either NAT Gateway or SSM VPC Endpoints.

## Validation Script

The VM includes a validation script that tests:

1. **DNS Resolution** - Verifies PrivateLink endpoints resolve to private IPs
2. **MongoDB Connection** - Tests connectivity via PrivateLink
3. **CRUD Operations** - Validates read/write capabilities

```bash
# On the VM
./validate-atlas
```

Expected output:
```
=== Atlas PrivateLink Validation ===
Target Host: cluster0-pl-0.xxxx.mongodb.net

-- DNS Resolution --
  OK: cluster0-shard-00-00.xxxx.mongodb.net -> 10.0.1.23 (private)
  OK: cluster0-shard-00-01.xxxx.mongodb.net -> 10.0.2.45 (private)
  OK: cluster0-shard-00-02.xxxx.mongodb.net -> 10.0.1.67 (private)

-- MongoDB Connection --
  OK: Connected successfully

-- CRUD Test --
  OK: Insert, Read, Delete successful

=== Summary ===
DNS Resolution: PASS
Connection:     PASS
CRUD Test:      PASS

Result: ALL TESTS PASSED - PrivateLink is working correctly!
```

## Troubleshooting

### mongosh not installed

If cloud-init couldn't install mongosh (no internet during boot):

```bash
# On the VM
./install-mongosh.sh
```

### Connection timeout

Check that:
1. Private Hosted Zone for `*.mongodb.net` is associated with your VPC
2. Security groups allow traffic on ports 1024-65535 from VPC CIDR
3. DNS resolution returns private IPs (not public)

```bash
# Test DNS
dig +short _mongodb._tcp.cluster0-pl-0.xxxx.mongodb.net SRV
```

### SSM Session Manager not working

SSM requires connectivity to AWS SSM endpoints. Either:
- Enable NAT Gateway (`validation_vm_create_nat_gateway = true`)
- Create SSM VPC Endpoints (`validation_vm_create_ssm_vpc_endpoints = true`)

### View cloud-init logs

```bash
sudo cat /var/log/cloud-init-output.log
```

## Outputs

| Output | Description |
|--------|-------------|
| `project_id` | Atlas project ID |
| `cluster_id` | Atlas cluster ID |
| `connection_string` | Private endpoint connection string |
| `privatelink` | PrivateLink endpoint status per region |
| `encryption` | KMS encryption configuration |
| `backup_export` | S3 backup export configuration |
| `validation_vm` | VM details and access commands |
| `validation_vm_networking` | NAT Gateway, EIC Endpoint details |

## Clean Up

```bash
terraform destroy
```

**Note:** NAT Gateway and EIC Endpoint will be removed, stopping any associated costs.

## Cost Considerations

| Resource | Cost |
|----------|------|
| NAT Gateway | ~$0.045/hr + data transfer |
| VPC Endpoints (SSM) | ~$0.01/hr per endpoint per AZ |
| EC2 Instance Connect Endpoint | Free |
| Validation VM (t3.micro) | ~$0.0104/hr |
| Atlas Cluster | Varies by tier |

To minimize costs:
- Destroy the validation VM after testing: `terraform destroy -target=module.validation_vm`
- Use SSM VPC Endpoints instead of NAT Gateway for long-running environments
