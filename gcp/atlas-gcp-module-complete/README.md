# Atlas on GCP - Complete Example

This example deploys a fully configured MongoDB Atlas environment on GCP, including an Atlas project, a sharded cluster, GCP PrivateLink connectivity via Private Service Connect (PSC), and backup export to Google Cloud Storage.

## What Gets Deployed

This example creates the following resources:

### MongoDB Atlas Resources
- **Atlas Project** — A new project in your Atlas organization with optional IP access list entries.
- **Sharded Cluster** — A 2-shard cluster on GCP, distributed across the regions you specify. Electable node counts are automatically inferred based on the number of regions (or can be overridden per region).

### GCP Resources
- **Cloud Provider Access** — An Atlas service account authorized to interact with your GCP project (auto-created by the module).
- **PSC Forwarding Rules** — One GCP forwarding rule and compute address per region, wired to the Atlas PrivateLink service for secure, private connectivity.
- **GCS Bucket** — A Google Cloud Storage bucket for Atlas backup exports (configurable to bring your own).

## Prerequisites

1. Install [Terraform](https://developer.hashicorp.com/terraform/install) (>= 1.9) to be able to run `terraform` [commands](#commands).
2. [Sign in](https://account.mongodb.com/account/login) or [create](https://account.mongodb.com/account/register) your MongoDB Atlas account.
3. Configure your Atlas [authentication](https://registry.terraform.io/providers/mongodb/mongodbatlas/latest/docs#authentication) method. This example assumes a service account with ORG_OWNER permission has been configured with the environment variables MONGODB_ATLAS_CLIENT_ID and MONGODB_ATLAS_CLIENT_SECRET

   **NOTE**: Service Accounts (SA) are the preferred authentication method. See [Grant Programmatic Access to an Organization](https://www.mongodb.com/docs/atlas/configure-api-access/#grant-programmatic-access-to-an-organization) for detailed instructions.

4. Authenticate your GCP CLI (`gcloud auth application-default login`), configure a service account key (`GOOGLE_APPLICATION_CREDENTIALS`), or use service account impersonation (set `service_account_email`).
5. Have a GCP project with at least one subnetwork per region where PSC endpoints will be created. The VPC is derived from the subnetwork — no separate network input is needed.

## Configuration

Copy the example tfvars to `terraform.tfvars` and fill in your values:

```sh
cp terraform.tfvars.example terraform.tfvars
```

At a minimum, provide:

| Variable | Description |
| --- | --- |
| `gcp_project_id` | Your GCP project ID |
| `atlas_org_id` | Your MongoDB Atlas Organization ID |
| `atlas_project_name` | Name for the new Atlas project |
| `atlas_cluster_name` | Name for the Atlas cluster |
| `regions` | List of regions with region name and subnetwork self_link (see [terraform.tfvars.example](./terraform.tfvars.example)). Accepts Atlas format (`US_EAST_4`) or GCP format (`us-east4`); normalized internally. |

Optional variables include `tags`, `ip_access_list`, `service_account_email`, and `backup_export_force_destroy`. See [variables.tf](./variables.tf) for full details.

## Commands

```sh
terraform init
# Configure authentication env vars (MONGODB_ATLAS_*, GOOGLE_*)
# Edit terraform.tfvars with your values
terraform apply -var-file terraform.tfvars
# Cleanup
terraform destroy -var-file terraform.tfvars
```

## Bring Your Own (BYO) Resources

This example creates all required GCP resources by default. If your organization requires using pre-existing resources, follow the inline comments in [atlas-gcp.tf](./atlas-gcp.tf) to swap in your own. A summary is provided below.

### BYO PSC Endpoints

By default, the module creates PSC forwarding rules in each region.

To use existing forwarding rules, update `atlas-gcp.tf` with the two-phase BYOE workflow:

```hcl
  # Phase 1: declare regions for Atlas endpoint service creation
  privatelink_byoe_regions = { east = "us-east4" }

  # Phase 2: after first apply, use privatelink_service_info output
  # to create your own forwarding rule, then complete the connection
  privatelink_byoe = {
    east = {
      ip_address           = google_compute_address.psc.address
      forwarding_rule_name = google_compute_forwarding_rule.psc.name
    }
  }
```

Use `module.atlas_gcp.privatelink_service_info` outputs to get the Atlas PrivateLink service details needed to connect your forwarding rule.

### BYO GCS Bucket

By default, the module creates a new GCS bucket for backup exports.

To use an existing GCS bucket, update `atlas-gcp.tf`:

```hcl
  # Replace:
  #   backup_export = local.backup_export_config
  # With:
  backup_export = {
    enabled     = true
    bucket_name = "your-existing-bucket-name"
  }
```

## Outputs

| Output | Description |
| --- | --- |
| `project_id` | MongoDB Atlas project ID |
| `cluster_id` | Atlas cluster ID |
| `connection_string` | Private endpoint SRV connection string |
| `backup_export` | Backup export configuration details |

## Feedback or Help

- For issues with these examples, open an issue in this repository.
- For issues with the Terraform provider, open an issue in the [provider repository](https://github.com/mongodb/terraform-provider-mongodbatlas).
