# Atlas Validation VM Module (GCP)

This module creates a private Ubuntu 22.04 Compute Engine VM that validates MongoDB Atlas connectivity through GCP Private Service Connect (PSC). It creates a temporary Atlas database user and installs the shared `validate-atlas` script to test the connection and basic CRUD operations.

## Features

- A private VM with no external IP in the supplied subnetwork.
- No GCP service account attached to the VM.
- Automatic selection of the first lexically sorted available zone in the subnet's region, with an explicit zone override.
- An optional IAP-only SSH firewall rule limited to `35.235.240.0/20` and the validation VM's network tag.
- An optional dedicated Cloud Router and Cloud NAT configuration scoped to the supplied subnetwork.
- A temporary Atlas database user with `readWrite` access to the `validation_test` database.
- Shared cloud-init and validation tooling used by the AWS, Azure, and GCP examples.

## Prerequisites

- An Atlas cluster with PSC configured and an associated private endpoint connection string.
- A GCP subnetwork that can resolve and route to the Atlas PSC endpoint.
- Outbound internet access from the subnetwork so cloud-init can install `mongosh`, unless `enable_cloud_nat = true`.
- IAM permissions for the Terraform identity to manage the required Compute Engine resources and Atlas database user. For Shared VPC, this includes the subnet's host project where the firewall, router, and NAT are created.
- `roles/iap.tunnelResourceAccessor` plus the Compute Engine SSH permissions required by your project for each user who connects through IAP. If OS Login is enabled, use `roles/compute.osAdminLogin` so the user can run the validation tooling as `ubuntu`. This module does not grant IAM roles.
- The `gcloud` CLI configured for the target project if you use the generated SSH commands.

## Usage

### Existing outbound internet access

```hcl
module "validation_vm" {
  source = "../modules/validation-vm"

  gcp_project_id = "example-project"
  subnetwork     = "https://www.googleapis.com/compute/v1/projects/example-project/regions/us-east4/subnetworks/atlas-psc"

  atlas_project_id        = "your-atlas-project-id"
  atlas_connection_string = "mongodb+srv://cluster0-pl-0.example.mongodb.net"
}
```

### Module-managed Cloud NAT and an explicit zone

```hcl
module "validation_vm" {
  source = "../modules/validation-vm"

  gcp_project_id = "example-project"
  subnetwork     = "https://www.googleapis.com/compute/v1/projects/example-project/regions/us-east4/subnetworks/atlas-psc"

  atlas_project_id        = "your-atlas-project-id"
  atlas_connection_string = "mongodb+srv://cluster0-pl-0.example.mongodb.net"

  zone             = "us-east4-b"
  enable_cloud_nat = true
}
```

Use only the private endpoint connection string associated with the selected PSC endpoint. The complete GCP example selects the connection string associated with its first configured region and fails if that association is unavailable. It does not fall back to a public or unrelated endpoint.

## Inputs

| Name | Description | Type | Default |
| --- | --- | --- | --- |
| `gcp_project_id` | GCP project where the VM is created and zones are queried. | `string` | Required. |
| `subnetwork` | Self-link of the subnetwork where the private VM is created. Optional networking resources are created in the subnet's project. | `string` | Required. |
| `atlas_project_id` | Atlas project where the temporary database user is created. | `string` | Required. |
| `atlas_connection_string` | Nullable Atlas private endpoint connection string. It must be non-null when the module is enabled. | `string` | Required. |
| `zone` | Compute Engine zone for the VM. It must belong to the subnetwork's region. When null, the first sorted available zone is selected. | `string` | `null`. |
| `machine_type` | Compute Engine machine type for the validation VM. | `string` | `"e2-micro"`. |
| `create_iap_ssh_firewall` | Create the targeted TCP port 22 firewall rule for IAP. | `bool` | `true`. |
| `enable_cloud_nat` | Create a dedicated router and subnet-scoped Cloud NAT for outbound internet access. | `bool` | `false`. |

## Outputs

| Name | Description |
| --- | --- |
| `instance_id` | Compute Engine instance ID. |
| `instance_name` | Compute Engine instance name. |
| `private_ip` | VM private IP address. |
| `zone` | Zone containing the VM. |
| `admin_username` | VM login username, `ubuntu`. |
| `ssh_command` | `gcloud compute ssh` command that connects through IAP. |
| `validation_command` | Command to run after connecting, including as an OS Login administrator. |
| `iap_firewall_rule_name` | IAP SSH firewall rule name, or null when rule creation is disabled. |
| `cloud_router_name` | Dedicated Cloud Router name, or null when Cloud NAT is disabled. |
| `cloud_nat_name` | Cloud NAT name, or null when Cloud NAT is disabled. |

## What Gets Created

### Always created

- A random password and temporary Atlas SCRAM database user with `readWrite` access to `validation_test`.
- A private Ubuntu 22.04 Compute Engine VM with no external IP or attached GCP service account.
- A VM-specific network tag.
- Cloud-init metadata that installs `mongosh` and writes the shared `validate-atlas` script.

### Conditionally created

| Resource | Condition |
| --- | --- |
| IAP SSH firewall rule | `create_iap_ssh_firewall = true`. |
| Dedicated Cloud Router and Cloud NAT | `enable_cloud_nat = true`. |

The IAP firewall rule permits TCP port 22 only from Google's IAP TCP forwarding range, `35.235.240.0/20`, and targets only the validation VM's network tag. IAP provides inbound access but does not provide outbound internet access.

The rule does not override other VPC ingress rules or hierarchical firewall policies. Review existing policy if IAP must be the only SSH path to the VM.

The optional Cloud NAT covers primary IP addresses throughout the selected subnetwork and is disabled by default. It therefore affects more than the validation VM. Enabling it can incur GCP charges. It can also conflict with an existing Cloud NAT configuration that already covers the subnetwork, so prefer existing egress when it is available. Cloud NAT still requires a suitable default route and permitted egress traffic.

The sorted automatic zone selection is deterministic for the currently available zones. Set `zone` explicitly if you need to prevent VM replacement when zone availability changes.

The VM is replaced when the rendered cloud-init configuration changes. This ensures that a changed endpoint, credential, or validation script is installed during first boot instead of leaving stale guest files.

## Accessing the VM

Use the `ssh_command` output:

```sh
terraform output -json validation_vm
gcloud compute ssh ubuntu@<instance-name> \
  --project <project-id> \
  --zone <zone> \
  --tunnel-through-iap
```

Then run the `validation_command` output:

```sh
sudo -H -u ubuntu /home/ubuntu/validate-atlas
```

If you connect directly as `ubuntu`, you can also run `./validate-atlas`.

## Credential Handling

The module injects the temporary Atlas username and password into the private endpoint connection string. The resulting credential is stored in Terraform state and in the VM's GCE `user-data` metadata, then written to `~/.atlas-connection` with mode `0600`.

Protect access to the Terraform state and GCE instance metadata. Destroying the module removes the temporary Atlas user and VM, but retained Terraform state versions or backups can continue to contain the credential.

## Troubleshooting

### `mongosh: command not found`

Cloud-init could not reach the Ubuntu or MongoDB package repositories. Provide existing outbound internet access or enable the optional Cloud NAT, then recreate the VM or install `mongosh` manually.

### IAP SSH connection fails

Confirm that:

- The connecting user has `roles/iap.tunnelResourceAccessor` and the required Compute Engine SSH or OS Login permissions.
- The IAP firewall rule exists, or an equivalent existing rule permits TCP port 22 from `35.235.240.0/20` to the VM's network tag.
- The IAP API and Compute Engine API are enabled.

### Atlas connection fails

Confirm that the connection string is associated with the PSC endpoint in the VM's region and that DNS from the VM resolves the Atlas hostname to the expected private address.

### Cloud-init is still running

```sh
cloud-init status --long
sudo tail -f /var/log/cloud-init-validation.log
```
