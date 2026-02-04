# Atlas Validation VM (Azure)

This Terraform module creates a small **Ubuntu VM inside your PrivateLink-enabled VNet** and pre-installs a validation runner (`validate-atlas`) to test that:

- All **unique** Atlas hosts **resolve to private IPs** (Private DNS is working)
- `mongosh` can **connect via the Private Endpoint**
- Basic **CRUD works over the private path**
- Optionally, **backups can be queried** using Atlas CLI (requires Atlas API keys)

Use it as a **“known-good client”** that lives in the same network as your Azure Private Endpoint, so troubleshooting is faster and repeatable.

## Prerequisites

- An Atlas cluster with an **Azure Private Endpoint** configured
- **Private DNS** configured so the Private Endpoint hostname(s) resolve to private IPs from the VNet where this VM runs
- Network routing/NSGs allow the VM subnet to reach the Private Endpoint

## What gets created

- **Azure Linux VM** (Ubuntu 22.04) with no public IP, in the subnet you provide
- **Azure NIC** attached to that subnet
- **Temporary Atlas database user** (SCRAM) with `readWriteAnyDatabase` on `admin` (for validation only)
- **Cloud-init provisioning** that installs:
  - `mongosh`
  - Atlas CLI (for optional backup validation)
  - `validate-atlas` script + a pre-configured connection string file

## How it works

1. Terraform creates a **temporary Atlas DB user** and generates a random password.
2. Terraform builds a connection string by injecting those credentials into the `atlas_connection_string` host(s).
3. The VM boots and cloud-init writes:
   - `~/.atlas-connection` (the full connection string with credentials)
   - `~/validate-atlas` (the validation script)
4. You log into the VM and run `./validate-atlas`.

The script validates DNS and connectivity from inside the VNet.

## Access modes (important)

This module supports two access patterns:

- **Default: Serial Console (no SSH key required)**  
  If `admin_ssh_public_key` is empty/null, the VM is configured for **password auth** and you access it via: Azure Portal → VM → **Serial console**. A random password is generated and exposed as a sensitive Terraform output.

- **Optional: Azure Bastion + SSH**  
  If `admin_ssh_public_key` is provided, the VM disables password auth and enables SSH key auth. The module will also create **Azure Bastion (Standard)** resources so you can SSH without opening inbound SSH from the internet.

**Note on Bastion subnet**: this module creates an `AzureBastionSubnet` with CIDR `10.0.255.0/26`. If that conflicts with your VNet/subnet plan, you’ll need to adjust the module before using Bastion.

### Connecting via Azure Bastion (when enabled)

When Bastion mode is enabled, the VM still has **no public IP**. Typical access is:

- Azure Portal → Virtual Machines → the validation VM → **Connect** → **Bastion**
- Authenticate with username `azureuser` and your SSH private key that matches `admin_ssh_public_key`

## Usage

Minimal example:

```hcl
module "validation_vm" {
  source = "../modules/validation-vm"

  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  subnet_id            = azurerm_subnet.workload.id

  # Leave empty to use Serial Console access (default)
  # Set to a public key string to enable Bastion + SSH access.
  admin_ssh_public_key = var.validation_vm_ssh_public_key

  atlas_project_id        = mongodbatlas_project.this.id
  atlas_connection_string = var.atlas_privatelink_connection_string

  # Optional: enables backup validation if you also provide Atlas API keys at runtime
  atlas_cluster_name = var.atlas_cluster_name
}
```

### Connection string input

`atlas_connection_string` should be the **Private Endpoint** connection string. The module supports:

- SRV: `mongodb+srv://<host>` (with or without credentials)
- Standard: `mongodb://<host1>:<port>,<host2>:<port>/?replicaSet=...`

## Running the validation

After you log into the VM:

```bash
cd ~
./validate-atlas
```

### Getting the Serial Console password

If you’re using Serial Console mode, the password is exposed as a **sensitive** Terraform output:

```bash
terraform output -raw validation_vm_admin_password
```

If you don’t have a top-level output yet, add this to your root module:

```hcl
output "validation_vm_admin_password" {
  value     = module.validation_vm.admin_password
  sensitive = true
}
```

Useful options:

```bash
./validate-atlas --help

# Fail fast (handy for CI/CD-style gating)
./validate-atlas --strict

# Override the connection string (otherwise it reads ~/.atlas-connection)
./validate-atlas 'mongodb+srv://...'

# Optional: also test that the public endpoint is blocked (network isolation)
./validate-atlas 'mongodb+srv://PRIVATE-PL-URI' 'mongodb+srv://PUBLIC-URI'
```

### Optional: backup validation (Atlas CLI)

If you want the script to query backups/snapshots, export Atlas API keys on the VM before running:

```bash
export MONGODB_ATLAS_PUBLIC_API_KEY="..."
export MONGODB_ATLAS_PRIVATE_API_KEY="..."
./validate-atlas
```


For deeper background on Atlas backups (what they are, restore behavior, and the exact permission model), see MongoDB’s docs:

- [Back Up, Restore, and Archive Data (Atlas)](https://www.mongodb.com/docs/atlas/backup-restore-cluster/)

Practical note for this VM:

- **Listing snapshots / monitoring restore jobs** generally requires **Project Read Only** access (or higher) on the project.
- **Managing backups / starting restores** requires elevated roles (see the doc above for the authoritative requirements).

## Inputs

| Name | Description | Type | Default |
|------|-------------|------|---------|
| `resource_group_name` | Azure Resource Group name | `string` | (required) |
| `location` | Azure region for the VM | `string` | (required) |
| `subnet_id` | Subnet ID for the VM (must be in a VNet that can resolve Private DNS and route to the Private Endpoint) | `string` | (required) |
| `admin_ssh_public_key` | If set, enables Bastion+SSH key auth; if empty, uses Serial Console + password auth | `string` | `""` |
| `atlas_project_id` | Atlas Project ID (used to create the temporary DB user) | `string` | (required) |
| `atlas_connection_string` | Atlas **Private Endpoint** connection string (SRV or standard) | `string` | (required) |
| `atlas_cluster_name` | Cluster name (only needed for optional backup validation via Atlas CLI) | `string` | `""` |

## Outputs

| Name | Description |
|------|-------------|
| `vm_name` | VM name (for Azure Portal navigation) |
| `admin_username` | Login username (`azureuser`) |
| `admin_password` | Password for Serial Console access (only when Serial Console mode is used) |
| `access` | Human-readable hint: Serial Console vs Bastion+SSH |

## Backup Restore Testing

The validation VM can verify connectivity & backup configuration, but backup restore testing requires additional steps.

### Option 1: Restore via Atlas UI (Recommended for Manual Testing)

See [Restore Your Cluster from a Snapshot](https://www.mongodb.com/docs/atlas/backup/cloud-backup/restore-from-snapshot/) in the Atlas documentation.

### Option 2: Restore via Atlas CLI

```bash
# List available snapshots
atlas backups snapshots list \
  --clusterName <cluster-name> \
  --projectId <project-id>

# Restore to a new cluster (CAUTION: creates billable resources)
atlas backups restores start \
  --clusterName <source-cluster> \
  --snapshotId <snapshot-id> \
  --targetClusterName <new-cluster-name> \
  --targetProjectId <project-id>

# Check restore job status
atlas backups restores list \
  --clusterName <cluster-name> \
  --projectId <project-id>
```

### Option 3: Check Exported Snapshots in Azure Storage

If backup export to Azure Blob Storage is configured in your Terraform, snapshots are automatically exported. Check them with:

```bash
# From any machine with Azure CLI access:
az storage blob list \
  --account-name <storage-account-name> \
  --container-name atlas-backups \
  --query "[].{Name:name, Size:properties.contentLength, Created:properties.createdOn}" \
  --output table
```

You can then download these exports for local restore testing if needed.

## Troubleshooting

- **Cloud-init still running / tools missing**:
  - `cloud-init status`
  - `sudo tail -f /var/log/cloud-init-validation.log`
- **DNS test fails (resolves to public IP or no records)**:
  - Ensure the **Private DNS zone** for Atlas Private Endpoint is created and **linked to the VNet** where this VM lives.
  - Ensure you used the **Private Endpoint connection string**.
- **Connection test fails**:
  - Confirm the Atlas cluster is up / not paused
  - Confirm any Atlas access controls (IP access list / PE configuration) allow this path
  - Validate the Private Endpoint is in `AVAILABLE` state and the VM subnet can route to it
