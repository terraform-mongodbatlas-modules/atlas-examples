# Shared Validation VM Resources

This directory contains shared cloud-init and validation script resources used by both AWS and Azure validation VM modules.

## Files

| File | Description |
|------|-------------|
| `cloud-init.yaml.tftpl` | Cloud-init template for Ubuntu VMs |
| `validate-atlas.sh` | Validation script that tests PrivateLink connectivity |

## Usage

These files are referenced by the cloud-specific validation VM modules:

- `aws/modules/validation-vm/main.tf`
- `azure/modules/validation-vm/main.tf`

Example usage in a module:

```hcl
locals {
  # Load shared validation script
  validate_script = file("${path.module}/../../shared/validation-vm/validate-atlas.sh")

  # Render shared cloud-init template
  cloud_init = templatefile("${path.module}/../../shared/validation-vm/cloud-init.yaml.tftpl", {
    admin_username    = local.admin_username  # "ubuntu" for AWS, "azureuser" for Azure
    validate_script   = local.validate_script
    connection_string = local.connection_string_with_creds
  })
}
```

## Template Variables

| Variable | Description | AWS Value | Azure Value |
|----------|-------------|-----------|-------------|
| `admin_username` | VM admin user | `ubuntu` | `azureuser` |
| `validate_script` | Contents of validate-atlas.sh | (same) | (same) |
| `connection_string` | MongoDB connection string with credentials | (same) | (same) |

## Validation Script

The `validate-atlas.sh` script performs the following tests:

1. **MongoDB Connection** - Verifies mongosh can connect via PrivateLink
2. **CRUD Operations** - Tests insert, read, update, delete operations
3. **Cluster Info** - Displays MongoDB version and topology

### Usage on VM

```bash
# Run with pre-configured connection string
./validate-atlas

# Run in strict mode (exit on first failure)
./validate-atlas --strict

# Override connection string
./validate-atlas 'mongodb+srv://user:pass@cluster.mongodb.net'

# Show help
./validate-atlas --help
```

## Modifying Shared Resources

When updating these files, changes will affect both AWS and Azure validation VMs.

Test changes in both environments before committing.
