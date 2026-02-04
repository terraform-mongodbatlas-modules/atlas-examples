# Atlas Validation VM Module

Terraform module that creates an Azure VM for validating MongoDB Atlas connectivity over PrivateLink.

## Features

- **Bastion/SSH access** - Connect via Azure Bastion or direct SSH (default)
- **Temporary database user** - Auto-created for SCRAM authentication
- **Pre-installed tools** - mongosh, validation scripts
- **Private IP verification** - Confirms traffic uses PrivateLink
- **Serial Console** - Optional alternative access method (no SSH port 22 required)

## Usage

This module can be invoked from `atlas-azure-module-complete` or any other Azure example in this repository.

### From atlas-azure-module-complete

Add the following to your example configuration:

```hcl
module "validation_vm" {
  source = "../modules/validation-vm"
  count  = var.enable_validation_vm ? 1 : 0

  resource_group_name  = var.azure_resource_group_name
  location             = var.regions[0].azure_location
  subnet_id            = var.regions[0].subnet_id
  admin_ssh_public_key = var.validation_vm_ssh_key

  atlas_project_id = module.atlas_project.id

  # Use the first region's private endpoint SRV connection string
  # This works for both sharded clusters (where private_srv is empty) and replica sets
  atlas_connection_string = try(
    module.atlas_cluster.connection_strings.private_endpoint[0].srv_connection_string,
    module.atlas_cluster.connection_strings.private_srv
  )

  depends_on = [module.atlas_azure]
}
```

Add these variables to `variables.tf`:

```hcl
# Validation VM
# ----------------------------------------------------
variable "enable_validation_vm" {
  description = "Deploy a validation VM to test Atlas deployment over PrivateLink"
  type        = bool
  default     = false
}

variable "validation_vm_ssh_key" {
  description = "SSH public key for validation VM access. Required if enable_validation_vm is true."
  type        = string
  default     = null
}
```

Add this output to `outputs.tf`:

```hcl
output "validation_vm" {
  description = "Validation VM details (if enabled)"
  value = var.enable_validation_vm ? {
    vm_name                      = module.validation_vm[0].vm_name
    private_ip                   = module.validation_vm[0].private_ip_address
    admin_username               = module.validation_vm[0].admin_username
    ssh_access                   = module.validation_vm[0].ssh_access
    database_username            = module.validation_vm[0].database_username
    validate_privatelink_command = module.validation_vm[0].validate_privatelink_command
    validate_connection_command  = module.validation_vm[0].validate_connection_command
    validate_crud_command        = module.validation_vm[0].validate_crud_command
  } : null
  sensitive = true
}
```

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| `resource_group_name` | Azure Resource Group name | `string` | - | yes |
| `location` | Azure region | `string` | - | yes |
| `subnet_id` | Subnet ID (same VNet as Atlas PE) | `string` | - | yes |
| `admin_ssh_public_key` | SSH public key for Bastion/SSH access | `string` | - | yes |
| `atlas_project_id` | Atlas Project ID | `string` | - | yes |
| `atlas_connection_string` | Atlas private endpoint SRV connection string (e.g., `mongodb+srv://cluster-pl-0.xxx.mongodb.net`) | `string` | - | yes |

**Hardcoded defaults** (edit in `main.tf` if needed):
- `name_prefix`: `atlas` (used for VM name: `atlas-validation-vm`, db user: `atlas-validation-user`)
- `vm_size`: `Standard_B1s`
- `admin_username`: `azureuser`
- `tags`: `{ Purpose = "Atlas Connectivity Validation", ManagedBy = "Terraform" }`

## Outputs

| Name | Description |
|------|-------------|
| `vm_id` | VM resource ID |
| `vm_name` | VM name |
| `private_ip_address` | Private IP address |
| `admin_username` | Admin username for SSH access |
| `ssh_access` | Bastion/SSH access instructions |
| `database_username` | Temporary database user username |
| `database_password` | Temporary database user password (sensitive) |
| `validate_privatelink_command` | Comprehensive PrivateLink validation (recommended) |
| `validate_connection_command` | Connection test with private IP verification |
| `validate_crud_command` | CRUD operations test |

## Validation Scripts

The VM comes with pre-installed validation scripts that verify connectivity is happening over PrivateLink (private network).

### Comprehensive PrivateLink Validation (Recommended)

```bash
# Full PrivateLink validation: private DNS, private IP resolution, connection test
./validate-privatelink 'mongodb+srv://user:pass@cluster-pl-0.xxxxx.mongodb.net'

# Optional: Also verify public path is blocked (network isolation)
./validate-privatelink 'mongodb+srv://user:pass@cluster-pl-0.xxxxx.mongodb.net' \
                       'mongodb+srv://user:pass@cluster.xxxxx.mongodb.net'
```

This script:
1. Verifies DNS resolves to private IPs (10.x, 172.16-31.x, 192.168.x)
2. Tests MongoDB connection succeeds
3. Optionally verifies public connection is blocked

### Connection Test with Private IP Verification

```bash
# Test connection and verify private IP resolution
./validate-connection 'mongodb+srv://user:pass@cluster-pl-0.xxxxx.mongodb.net'
```

### CRUD Operations Test

```bash
# Test CRUD operations over PrivateLink
./validate-crud 'mongodb+srv://user:pass@cluster-pl-0.xxxxx.mongodb.net'
```

## Accessing the VM

### Via Azure Bastion (Recommended)

1. Azure Portal → Virtual Machines → `<vm_name>`
2. Connect → Bastion
3. Enter username `azureuser` and select SSH Private Key authentication
4. Upload or paste your private key

### Via Direct SSH

If you have network access to the VM's private IP:

```bash
ssh -i ~/.ssh/your_private_key azureuser@<private_ip>
```

### Via Serial Console (Optional)

To enable Serial Console access (no SSH port 22 required), see the inline comments in `main.tf` for instructions on enabling password authentication.

## Notes

- The VM is deployed in the same subnet as the Atlas Private Endpoint for connectivity
- A temporary database user with `readWriteAnyDatabase` role is created for validation
- Boot diagnostics are enabled for Serial Console access
