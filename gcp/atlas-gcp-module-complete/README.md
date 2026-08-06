# Atlas on GCP - Complete Example

This example deploys a fully configured MongoDB Atlas environment on GCP, including an Atlas project, a sharded cluster, GCP PrivateLink connectivity via Private Service Connect (PSC), backup export to Google Cloud Storage, and an optional validation VM.

## What Gets Deployed

This example creates the following resources:

### MongoDB Atlas Resources
- **Atlas Project** — A new project in your Atlas organization with optional IP access list entries.
- **Sharded Cluster** — A 2-shard cluster on GCP, distributed across the regions you specify. Electable node counts are automatically inferred based on the number of regions (or can be overridden per region).

### GCP Resources
- **Cloud Provider Access** — An Atlas service account authorized to interact with your GCP project (auto-created by the module).
- **PSC Forwarding Rules** — One GCP forwarding rule and compute address per region, wired to the Atlas PrivateLink service for secure, private connectivity.
- **GCS Bucket** — A Google Cloud Storage bucket for Atlas backup exports (configurable to bring your own).

### Validation (Optional, enabled by default)

- **Validation VM**: A private Ubuntu 22.04 Compute Engine VM in the first configured region's PSC subnetwork.
  - The VM has no external IP.
  - SSH access uses IAP. By default, the example creates a targeted firewall rule that permits TCP port 22 only from `35.235.240.0/20` to the VM's network tag.
  - The VM uses the first sorted available zone in the subnet's region unless `validation_vm_zone` is set.
  - Optional subnet-scoped Cloud NAT is available when the subnet has no existing outbound internet access.
  - Set `enable_validation_vm = false` to skip validation resources.
  - See [Validating the Deployment](#validating-the-deployment) and the [validation-vm module README](../modules/validation-vm/README.md) for details.

## Prerequisites

1. Install [Terraform](https://developer.hashicorp.com/terraform/install) (>= 1.9) to be able to run `terraform` [commands](#commands).
2. [Sign in](https://account.mongodb.com/account/login) or [create](https://account.mongodb.com/account/register) your MongoDB Atlas account.
3. Configure your Atlas [authentication](https://registry.terraform.io/providers/mongodb/mongodbatlas/latest/docs#authentication) method. This example assumes a service account with ORG_OWNER permission has been configured with the environment variables MONGODB_ATLAS_CLIENT_ID and MONGODB_ATLAS_CLIENT_SECRET

   **NOTE**: Service Accounts (SA) are the preferred authentication method. See [Grant Programmatic Access to an Organization](https://www.mongodb.com/docs/atlas/configure-api-access/#grant-programmatic-access-to-an-organization) for detailed instructions.

4. Authenticate your GCP CLI (`gcloud auth application-default login`), configure a service account key (`GOOGLE_APPLICATION_CREDENTIALS`), or use service account impersonation (set `service_account_email`).
5. Have a GCP project with at least one subnetwork per region where PSC endpoints will be created. The VPC is derived from the subnetwork — no separate network input is needed.
6. If validation is enabled, provide outbound internet access from the first region's subnetwork so cloud-init can install `mongosh`, or set `validation_vm_enable_cloud_nat = true`.
7. To connect to the validation VM through IAP, grant the connecting user `roles/iap.tunnelResourceAccessor` and the Compute Engine SSH permissions required by your project. If OS Login is enabled, use `roles/compute.osAdminLogin` so the user can run the validation tooling as `ubuntu`. This example does not grant IAM roles.

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

Optional variables include `tags`, `ip_access_list`, `service_account_email`, `backup_export_force_destroy`, `backup_export_bucket_name`, and the validation settings:

| Variable | Default | Description |
| --- | --- | --- |
| `enable_validation_vm` | `true` | Create the validation VM and temporary Atlas database user. |
| `validation_vm_zone` | `null` | Override the automatically selected zone. The zone must belong to the first subnetwork's region. |
| `validation_vm_machine_type` | `"e2-micro"` | Compute Engine machine type for the validation VM. |
| `validation_vm_create_iap_ssh_firewall` | `true` | Create the targeted IAP SSH firewall rule. |
| `validation_vm_enable_cloud_nat` | `false` | Create a dedicated, subnet-scoped Cloud Router and Cloud NAT. |

See [variables.tf](./variables.tf) for full details.

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

1. Set `enable_validation_vm = false`, set `privatelink_endpoints = []`, and configure `privatelink_byo_endpoint` (Atlas-side services). Apply.
2. Create `google_compute_address` and `google_compute_forwarding_rule` using `module.atlas_gcp.privatelink_service_info`.
3. Set `privatelink_byo_service` with `ip_address` and `forwarding_rule_name` per key, then set `enable_validation_vm = true`. Apply again.

For module-managed endpoints, `privatelink` and `privatelink_service_info` output map keys use lowercase GCP format (`us-east4`) in atlas-gcp v0.2.0. BYO outputs retain the configured map keys, such as `east`.

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

## Validating the Deployment

When `enable_validation_vm = true` (the default), the example deploys a private VM into the first configured region's PSC subnetwork. It selects the private endpoint connection string associated with that region. Validation fails if the association is unavailable instead of falling back to a public or unrelated endpoint.

After `terraform apply` completes:

1. Inspect the `validation_vm` output for the instance name, zone, username, and generated commands.
2. Run the generated `ssh_command`, or connect with:

   ```sh
   gcloud compute ssh ubuntu@<instance-name> \
     --project <project-id> \
     --zone <zone> \
     --tunnel-through-iap
   ```

3. Run the generated `validation_command` on the VM to verify the private connection and CRUD operations. If you connect directly as `ubuntu`, you can also run `./validate-atlas`.

IAP provides inbound SSH access only. Cloud-init still needs outbound internet access to install `mongosh`. If the subnet does not already have egress through an existing Cloud NAT, proxy, or other approved route, set `validation_vm_enable_cloud_nat = true`.

The targeted IAP rule does not override other VPC ingress rules or hierarchical firewall policies. Review existing policy if IAP must be the only SSH path to the VM.

The optional Cloud NAT creates a dedicated router and NAT configuration covering primary IP addresses throughout the first region's subnetwork, so it affects more than the validation VM. It can incur GCP charges and can conflict with an existing Cloud NAT that already covers the subnet. It still requires a suitable default route and permitted egress traffic. Leave it disabled when existing egress is available.

The temporary Atlas database credential is stored in Terraform state and in the VM's GCE `user-data` metadata, then written to `~/.atlas-connection`. Protect access to both surfaces. Retained Terraform state versions or backups can continue to contain the credential after the validation resources are destroyed.

Set `enable_validation_vm = false` to skip the VM, temporary database user, IAP firewall rule, and optional NAT resources.

For detailed inputs, outputs, IAM requirements, and troubleshooting, see the [validation-vm module README](../modules/validation-vm/README.md).

## Outputs

| Output | Description |
| --- | --- |
| `project_id` | MongoDB Atlas project ID |
| `cluster_id` | Atlas cluster ID |
| `connection_string` | Private endpoint SRV connection string |
| `backup_export` | Backup export configuration details |
| `validation_vm` | Validation VM details and access commands, or null when validation is disabled |

## Feedback or Help

- For issues with these examples, open an issue in this repository.
- For issues with the Terraform provider, open an issue in the [provider repository](https://github.com/mongodb/terraform-provider-mongodbatlas).
