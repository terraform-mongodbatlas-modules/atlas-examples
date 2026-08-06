# Shared Validation VM Resources

This directory contains shared cloud-init and validation script resources used by the AWS, Azure, and GCP validation VM modules.

## Files

| File | Description |
|------|-------------|
| `cloud-init.yaml.tftpl` | Cloud-init template for Ubuntu VMs |
| `validate-atlas.sh` | Validation script that tests private endpoint connectivity |

## Usage

These files are referenced by the cloud-specific validation VM modules:

- `aws/modules/validation-vm/main.tf`
- `azure/modules/validation-vm/main.tf`
- `gcp/modules/validation-vm/main.tf`

Example usage in a module:

```hcl
locals {
  # Load shared validation script
  # path.module is <provider>/modules/validation-vm/, so ../../../ reaches the repo root
  validate_script = file("${path.module}/../../../shared/validation-vm/validate-atlas.sh")

  # Render shared cloud-init template
  cloud_init = templatefile("${path.module}/../../../shared/validation-vm/cloud-init.yaml.tftpl", {
    admin_username    = local.admin_username  # "ubuntu" for AWS/GCP, "azureuser" for Azure
    validate_script   = local.validate_script
    connection_string = local.connection_string_with_creds
  })
}
```

## Template Variables

| Variable | Description | AWS Value | Azure Value | GCP Value |
|----------|-------------|-----------|-------------|-----------|
| `admin_username` | VM admin user | `ubuntu` | `azureuser` | `ubuntu` |
| `validate_script` | Contents of validate-atlas.sh | (same) | (same) | (same) |
| `connection_string` | MongoDB connection string with credentials | (same) | (same) | (same) |

## Validation Script

The `validate-atlas.sh` script performs the following tests:

1. **MongoDB Connection** - Verifies mongosh can connect through the configured private endpoint
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

## Security and Network Notes

The cloud-specific modules render a temporary Atlas database credential into the connection string. That credential is stored in Terraform state and in the VM's cloud-init or user-data metadata, then written to `~/.atlas-connection` with mode `0600`. Protect access to Terraform state, instance metadata, and retained state history.

Cloud-init downloads packages from Ubuntu and MongoDB repositories. The VM subnet therefore needs outbound internet access through existing infrastructure or through the cloud-specific optional egress configuration. Access mechanisms such as GCP IAP, AWS SSM, and Azure Bastion do not automatically provide package egress.

Each cloud module documents its endpoint-selection, IAM, access, egress, and cost requirements. The GCP complete example requires a private endpoint connection string associated with its first configured region and does not fall back to a public or unrelated endpoint.

## Modifying Shared Resources

When updating these files, changes will affect AWS, Azure, and GCP validation VMs.

Test changes in all three environments before committing.
