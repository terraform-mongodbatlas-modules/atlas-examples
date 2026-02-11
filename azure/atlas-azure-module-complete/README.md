# Atlas on Azure - Complete Example

This example deploys a fully configured MongoDB Atlas environment in your Azure account, including an Atlas project, a sharded cluster, Azure PrivateLink connectivity, backup export to Azure Blob Storage, and an optional validation VM to verify the deployment.

## What Gets Deployed

This example creates the following resources:

### MongoDB Atlas Resources
- **Atlas Project** — A new project in your Atlas organization with optional IP access list entries.
- **Sharded Cluster** — A 2-shard cluster on Azure, distributed across the regions you specify. Electable node counts are automatically inferred based on the number of regions (or can be overridden per region).

### Azure Resources
- **Service Principal** — An Azure AD Service Principal for Atlas to interact with your Azure subscription (configurable to bring your own).
- **Private Endpoints** — One Azure Private Endpoint per region, wired to the Atlas PrivateLink service for secure, private connectivity.
- **Storage Account & Container** — An Azure Storage Account and blob container for Atlas backup exports (configurable to bring your own).

### Validation (Optional)
- **Validation VM** — A Linux VM deployed into the first region's subnet to verify Atlas connectivity over PrivateLink. Accessible via Azure Serial Console (default) or Azure Bastion (if an SSH key is provided).

## Prerequisites

1. Install [Terraform](https://developer.hashicorp.com/terraform/install) (>= 1.9) to be able to run `terraform` [commands](#commands).
2. [Sign in](https://account.mongodb.com/account/login) or [create](https://account.mongodb.com/account/register) your MongoDB Atlas account.
3. Configure your Atlas [authentication](https://registry.terraform.io/providers/mongodb/mongodbatlas/latest/docs#authentication) method.  This example assumes a service account with ORG_OWNER permission has been configured with the environment variables MONGODB_ATLAS_CLIENT_ID and MONGODB_ATLAS_CLIENT_SECRET

   **NOTE**: Service Accounts (SA) is the preferred authentication method. See [Grant Programmatic Access to an Organization](https://www.mongodb.com/docs/atlas/configure-api-access/#grant-programmatic-access-to-an-organization) for detailed instructions.

4. Authenticate your Azure CLI (`az login`) or configure Azure service principal credentials (`ARM_*` environment variables).
5. Have an existing Azure Resource Group and at least one subnet where Private Endpoints and the validation VM will be created.

## Configuration

Copy the example variables file and fill in your values:

```sh
cp terraform.tfvars.example terraform.tfvars
```

At a minimum, provide:

| Variable | Description |
|---|---|
| `atlas_org_id` | Your MongoDB Atlas Organization ID |
| `atlas_project_name` | Name for the new Atlas project |
| `atlas_cluster_name` | Name for the Atlas cluster |
| `azure_resource_group_name` | Azure Resource Group for Private Endpoints, backup storage, and the validation VM |
| `regions` | List of regions with Atlas region name, Azure subnet ID, and Azure location (see [terraform.tfvars.example](./terraform.tfvars.example)) |

Optional variables include `azure_subscription_id`, `tags`, `ip_access_list`, `enable_validation_vm`, and `validation_vm_ssh_key`. See [variables.tf](./variables.tf) for full details.

## Commands

```sh
terraform init
# Configure authentication env vars (MONGODB_ATLAS_*, ARM_*)
# Edit terraform.tfvars with your values
terraform apply -var-file terraform.tfvars
# Cleanup
terraform destroy -var-file terraform.tfvars
```

## Bring Your Own (BYO) Resources

This example creates all required Azure resources by default. If your organization requires using pre-existing resources, follow the inline comments in [atlas-azure.tf](./atlas-azure.tf) to swap in your own. A summary is provided below.

### BYO Service Principal

By default, the module creates a new Azure AD Service Principal.

To use an existing one, update `atlas-azure.tf`:

```hcl
  # Replace:
  #   create_service_principal = true
  # With:
  create_service_principal = false
  service_principal_id     = "<existing-service-principal-object-id>"
```

The `service_principal_id` must be the Azure AD **Object ID** of the existing principal.

### BYO Private Endpoints

By default, the module creates Azure Private Endpoints in each region.

To use existing Private Endpoints, update `atlas-azure.tf`:

```hcl
  # Replace:
  #   privatelink_endpoints = local.privatelink_endpoints
  # With:
  privatelink_byoe_locations = {
    eastus2 = "eastus2"
  }

  privatelink_byoe = {
    eastus2 = {
      azure_private_endpoint_id         = "<existing-private-endpoint-id>"
      azure_private_endpoint_ip_address = "<private-ip>"
    }
  }
```

Use `module.atlas_azure.privatelink_service_info` outputs to get the Atlas PrivateLink service details needed to connect your own endpoint.

### BYO Storage Account & Container

By default, the module creates a new Storage Account and blob container for backup exports.

To use an existing Storage Account, update `atlas-azure.tf`:

```hcl
  # Replace the `create_storage_account` block with:
  backup_export = {
    enabled            = true
    container_name     = "existing-container-name"
    storage_account_id = "/subscriptions/<sub>/resourceGroups/<rg>/providers/Microsoft.Storage/storageAccounts/<name>"
    create_container   = false
  }
```

Notes:
- `storage_account_id` must be the full Azure resource ID.
- Set `create_container = true` only if the container does **not** already exist.

## Validating the Deployment

When `enable_validation_vm = true` (the default), a Linux VM is deployed into the first region's subnet. After `terraform apply` completes:

1. Note the `validation_vm` output for VM name and username.
2. Retrieve the password: `terraform output -raw validation_vm_password`
3. Connect via **Azure Serial Console** (default) or **Azure Bastion** (if `validation_vm_ssh_key` was provided).
4. Run `./validate-atlas` on the VM to verify connectivity to your Atlas cluster over PrivateLink.

Set `enable_validation_vm = false` to skip deploying the validation VM.

## Outputs

| Output | Description |
|---|---|
| `project_id` | MongoDB Atlas project ID |
| `cluster_id` | Atlas cluster ID |
| `connection_string` | Private endpoint SRV connection string |
| `backup_export` | Backup export configuration details |
| `validation_vm` | Validation VM details (if enabled) |
| `validation_vm_password` | VM password for Serial Console login (sensitive) |

## Feedback or Help

- For issues with these examples, open an issue in this repository.
- For issues with the Terraform provider, open an issue in the [provider repository](https://github.com/mongodb/terraform-provider-mongodbatlas).
