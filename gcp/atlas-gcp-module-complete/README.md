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

Optional variables include `tags`, `ip_access_list`, `service_account_email`, `backup_export_force_destroy`, and `backup_export_bucket_name`. See [variables.tf](./variables.tf) for full details.

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

For user-managed forwarding rules, use the two-phase workflow in [atlas-gcp.tf](./atlas-gcp.tf) and the module [BYO Endpoint example](https://github.com/terraform-mongodbatlas-modules/terraform-mongodbatlas-atlas-gcp/tree/main/examples/privatelink_byoe):

1. Set `privatelink_endpoints = []` and configure `privatelink_byo_endpoint` (Atlas-side services). Apply.
2. Create `google_compute_address` and `google_compute_forwarding_rule` using `module.atlas_gcp.privatelink_service_info`.
3. Set `privatelink_byo_service` with `ip_address` and `forwarding_rule_name` per key. Apply again.

`privatelink` and `privatelink_service_info` output map keys use lowercase GCP format (`us-east4`) in atlas-gcp v0.2.0, regardless of Atlas-format region inputs in this example.

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

## Upgrading from atlas-gcp 0.1.x

- Pin `atlas-gcp` to `~> 0.2`, `atlas-project` to `~> 0.2`, and `mongodbatlas` to `~> 2.8`.
- Deployments that used this example on 0.1.x with Atlas-format regions need `moved` blocks for PrivateLink submodule keys. See the [v0.2.0 upgrade guide](https://github.com/terraform-mongodbatlas-modules/terraform-mongodbatlas-atlas-gcp/blob/main/docs/v0.2.0-upgrade-guide.md). Minimal example (repeat per region):
  ```hcl
  moved {
    from = module.atlas_gcp.module.privatelink["US_EAST_4"]
    to   = module.atlas_gcp.module.privatelink["us-east4"]
  }
  ```
- Rename `backup_export.create_bucket` to `create_gcs_bucket` in your root module. Upgrades may also show GCS lifecycle, versioning, and IAM role changes on the backup bucket (see upgrade guide).
- For per-region SRV on multi-region sharded clusters, set `privatelink_regional_mode = "auto"` on the atlas-gcp module (default is `"disabled"`).

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
