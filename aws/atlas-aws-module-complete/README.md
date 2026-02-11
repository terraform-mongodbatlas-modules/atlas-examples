# Atlas on AWS - Complete Example

This example deploys a fully configured MongoDB Atlas environment on AWS, including an Atlas project, a sharded cluster, AWS PrivateLink connectivity, backup export to S3, and an optional validation VM to verify the deployment.

## What Gets Deployed

This example creates the following resources:

### MongoDB Atlas Resources
- **Atlas Project** — A new project in your Atlas organization with optional IP access list entries.
- **Sharded Cluster** — A 2-shard cluster on AWS, distributed across the regions you specify. Electable node counts are automatically inferred based on the number of regions (or can be overridden per region).

### AWS Resources
- **Cloud Provider Access (IAM Role)** — An IAM role that Atlas assumes to interact with your AWS account (configurable to bring your own).
- **VPC Endpoints** — One AWS VPC Endpoint per region, wired to the Atlas PrivateLink service for secure, private connectivity.
- **S3 Bucket** — An S3 bucket for Atlas backup exports (configurable to bring your own).

### Validation (Optional, enabled by default)
- **Validation VM** — An EC2 instance deployed into the first region's private subnet to verify Atlas connectivity over PrivateLink. Accessible via SSM Session Manager (default) or EC2 Instance Connect Endpoint (if enabled). Set `enable_validation_vm = false` to skip. See [Validating the Deployment](#validating-the-deployment) and the [validation-vm module README](../modules/validation-vm/README.md) for full details.

## Prerequisites

1. Install [Terraform](https://developer.hashicorp.com/terraform/install) (>= 1.9) to be able to run `terraform` [commands](#commands).
2. [Sign in](https://account.mongodb.com/account/login) or [create](https://account.mongodb.com/account/register) your MongoDB Atlas account.
3. Configure your Atlas [authentication](https://registry.terraform.io/providers/mongodb/mongodbatlas/latest/docs#authentication) method. This example assumes a service account with ORG_OWNER permission has been configured with the environment variables MONGODB_ATLAS_CLIENT_ID and MONGODB_ATLAS_CLIENT_SECRET

   **NOTE**: Service Accounts (SA) are the preferred authentication method. See [Grant Programmatic Access to an Organization](https://www.mongodb.com/docs/atlas/configure-api-access/#grant-programmatic-access-to-an-organization) for detailed instructions.

4. Configure your AWS credentials (`AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` environment variables, AWS CLI profile, or IAM role).
5. Have the following AWS networking resources already created:

   **Per region:**
   - A VPC with DNS hostnames and DNS resolution enabled
   - At least 2 private subnets in different Availability Zones (for PrivateLink endpoint placement)

   **For the validation VM (optional, first region only):**
   - A public subnet with a route to an Internet Gateway (for NAT Gateway placement, so cloud-init can download packages)

## Configuration

Copy the example tfvars to `terraform.tfvars` and fill in your values:

```sh
cp terraform.tfvars.example terraform.tfvars
```

At a minimum, provide:

| Variable | Description |
| --- | --- |
| `atlas_org_id` | Your MongoDB Atlas Organization ID |
| `atlas_project_name` | Name for the new Atlas project |
| `atlas_cluster_name` | Name for the Atlas cluster |
| `regions` | List of regions with Atlas region name, VPC ID, and private subnet IDs (see [terraform.tfvars.example](./terraform.tfvars.example)) |

Optional variables include `aws_region`, `tags`, `ip_access_list`, `enable_validation_vm`, and validation VM networking/access variables. See [variables.tf](./variables.tf) for full details.

## Commands

```sh
terraform init
# Configure authentication env vars (MONGODB_ATLAS_*, AWS_*)
# Edit terraform.tfvars with your values
terraform apply -var-file terraform.tfvars
# Cleanup
terraform destroy -var-file terraform.tfvars
```

## Bring Your Own (BYO) Resources

This example creates all required AWS resources by default. If your organization requires using pre-existing resources, follow the inline comments in [atlas-aws.tf](./atlas-aws.tf) to swap in your own. A summary is provided below.

### BYO IAM Role

By default, the module creates a new IAM role for Atlas Cloud Provider Access.

To use an existing one, update `atlas-aws.tf`:

```hcl
  # Replace:
  #   cloud_provider_access = {
  #     create = true
  #   }
  # With:
  cloud_provider_access = {
    create       = false
    iam_role_arn = "arn:aws:iam::123456789012:role/your-atlas-role"
  }
```

The IAM role must have a trust policy allowing Atlas to assume it.

### BYO VPC Endpoints

By default, the module creates AWS VPC Endpoints in each region.

To use existing VPC Endpoints, update `atlas-aws.tf`:

```hcl
  # Replace:
  #   privatelink_endpoints = local.privatelink_endpoints
  # With:
  privatelink_endpoints = []  # Disable module-managed endpoints

  privatelink_byoe = [
    {
      region      = "us-east-1"
      endpoint_id = "vpce-0abc123def456789"
    }
  ]
```

Use `module.atlas_aws.privatelink_service_info` outputs to get the Atlas PrivateLink service details needed to connect your VPC Endpoint.

### BYO S3 Bucket

By default, the module creates a new S3 bucket for backup exports.

To use an existing S3 bucket, update `atlas-aws.tf`:

```hcl
  # Replace:
  #   backup_export = local.backup_export_config
  # With:
  backup_export = {
    enabled     = true
    bucket_name = "your-existing-bucket-name"
    create_s3_bucket = {
      enabled = false
    }
  }
```

Notes:
- The S3 bucket must have the correct IAM policy allowing Atlas to write.
- See Atlas documentation for the required bucket policy.

## Validating the Deployment

When `enable_validation_vm = true` (the default), an EC2 instance is deployed into the first region's private subnet. After `terraform apply` completes:

1. Note the `validation_vm` output for instance ID, username, and access commands.
2. Connect via **SSM Session Manager** (default, always available):
   ```sh
   aws ssm start-session --target <instance-id>
   ```
3. Or via **EC2 Instance Connect** (if `validation_vm_create_ec2_instance_connect_endpoint = true`):
   ```sh
   aws ec2-instance-connect ssh --instance-id <instance-id> --os-user ubuntu
   ```
4. Run `./validate-atlas` on the VM to verify connectivity to your Atlas cluster over PrivateLink.

To enable automatic package installation (mongosh, Atlas CLI) on the VM via cloud-init, provide `validation_vm_public_subnet_id` and `validation_vm_private_route_table_id` so the module can create a NAT Gateway for outbound internet access.

If cloud-init was unable to install packages (e.g. no NAT Gateway was configured), install mongosh manually once the subnet has outbound access. See the [official mongosh installation guide](https://www.mongodb.com/docs/mongodb-shell/install/).

Set `enable_validation_vm = false` to skip deploying the validation VM.

For troubleshooting VM connectivity or tooling issues, see the [validation-vm module troubleshooting guide](../modules/validation-vm/README.md#troubleshooting).

## Outputs

| Output | Description |
| --- | --- |
| `project_id` | MongoDB Atlas project ID |
| `cluster_id` | Atlas cluster ID |
| `connection_string` | Private endpoint SRV connection string |
| `backup_export` | Backup export configuration details |
| `validation_vm` | Validation VM details (if enabled) |

## Feedback or Help

- For issues with these examples, open an issue in this repository.
- For issues with the Terraform provider, open an issue in the [provider repository](https://github.com/mongodb/terraform-provider-mongodbatlas).
