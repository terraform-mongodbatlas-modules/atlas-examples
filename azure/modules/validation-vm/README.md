# Atlas Validation VM (Azure)

This Terraform module creates a small **Ubuntu VM inside your PrivateLink-enabled VNet** and pre-installs a validation runner (`validate-atlas`) to test that:

- `mongosh` can **connect via the Private Endpoint**
- Basic **CRUD works over the private path**

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
  - `validate-atlas` script + a pre-configured connection string file

## How it works

1. Terraform creates a **temporary Atlas DB user** and generates a random password.
2. Terraform builds a connection string by injecting those credentials into the `atlas_connection_string` host(s).
3. The VM boots and cloud-init writes:
   - `~/.atlas-connection` (the full connection string with credentials)
   - `~/validate-atlas` (the validation script)
4. You log into the VM and run `./validate-atlas`.

The script validates connectivity and CRUD from inside the VNet.

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
}
```

### Connection string input

Use the **Private Endpoint** connection string for `atlas_connection_string`. The module supports:

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

```

## Inputs

| Name | Description | Type | Default |
|------|-------------|------|---------|
| `resource_group_name` | Azure Resource Group name | `string` | (required) |
| `location` | Azure region for the VM | `string` | (required) |
| `subnet_id` | Subnet ID for the VM (must be in a VNet that can resolve Private DNS and route to the Private Endpoint) | `string` | (required) |
| `admin_ssh_public_key` | If set, enables Bastion+SSH key auth; if empty, uses Serial Console + password auth | `string` | `""` |
| `atlas_project_id` | Atlas Project ID (used to create the temporary DB user) | `string` | (required) |
| `atlas_connection_string` | Atlas **Private Endpoint** connection string (SRV or standard) | `string` | (required) |

## Outputs

| Name | Description |
|------|-------------|
| `vm_name` | VM name (for Azure Portal navigation) |
| `admin_username` | Login username (`azureuser`) |
| `admin_password` | Password for Serial Console access (only when Serial Console mode is used) |
| `access` | Human-readable hint: Serial Console vs Bastion+SSH |

## Troubleshooting

- **Cloud-init still running / tools missing**:
  - `cloud-init status`
  - `sudo tail -f /var/log/cloud-init-validation.log`
- **Connection test fails**:
  - Confirm the Atlas cluster is up / not paused
  - Confirm any Atlas access controls (IP access list / PE configuration) allow this path
  - Validate the Private Endpoint is in `AVAILABLE` state and the VM subnet can route to it
