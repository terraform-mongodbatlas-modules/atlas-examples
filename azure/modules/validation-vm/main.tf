# ---------------------------------------------------------------------------
# Atlas Connectivity Validation VM Module
# ---------------------------------------------------------------------------
# Creates an Azure VM to validate MongoDB Atlas connectivity over PrivateLink.
# Location: azure/modules/validation-vm
# Designed to be called as a module from any Azure example in this repository.
#
# Features:
#   - Serial Console access (no SSH port 22 required)
#   - Managed Identity (for OIDC authentication option)
#   - Temporary database user for SCRAM authentication
#   - Pre-installed mongosh and validation scripts
# ---------------------------------------------------------------------------

locals {
  vm_name = var.name_prefix != "" ? "${var.name_prefix}-validation-vm" : "atlas-validation-vm"

  common_tags = merge(
    {
      "Purpose"   = "Atlas Connectivity Validation"
      "ManagedBy" = "Terraform"
    },
    var.tags
  )

  # Extract host from connection string (remove mongodb+srv:// prefix)
  cluster_host = replace(var.atlas_connection_string, "mongodb+srv://", "")

  # Full connection string with credentials
  connection_string_with_creds = "mongodb+srv://${mongodbatlas_database_user.validation.username}:${random_password.db_user.result}@${local.cluster_host}"

  # Cloud-init script to install MongoDB tools and validation scripts
  cloud_init = templatefile("${path.module}/cloud-init.yaml.tftpl", {
    admin_username = var.admin_username
  })
}

# ---------------------------------------------------------------------------
# Random Passwords
# ---------------------------------------------------------------------------
resource "random_password" "db_user" {
  length  = 24
  special = false # Avoid URL encoding issues in connection string
}

resource "random_password" "vm_admin" {
  length           = 20
  special          = true
  override_special = "!@#$%^&*"
}

# ---------------------------------------------------------------------------
# Temporary Database User (for SCRAM authentication)
# ---------------------------------------------------------------------------

resource "mongodbatlas_database_user" "validation" {
  project_id         = var.atlas_project_id
  username           = "${var.name_prefix}-validation-user"
  password           = random_password.db_user.result
  auth_database_name = "admin"

  roles {
    role_name     = "readWriteAnyDatabase"
    database_name = "admin"
  }

  labels {
    key   = "purpose"
    value = "validation-vm-temporary"
  }
}

# ---------------------------------------------------------------------------
# Network Interface
# ---------------------------------------------------------------------------
resource "azurerm_network_interface" "validation" {
  name                = "${local.vm_name}-nic"
  location            = var.location
  resource_group_name = var.resource_group_name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = var.subnet_id
    private_ip_address_allocation = "Dynamic"
  }

  tags = local.common_tags
}

# ---------------------------------------------------------------------------
# Virtual Machine
# ---------------------------------------------------------------------------
resource "azurerm_linux_virtual_machine" "validation" {
  name                = local.vm_name
  resource_group_name = var.resource_group_name
  location            = var.location
  size                = var.vm_size

  admin_username                  = var.admin_username
  admin_password                  = random_password.vm_admin.result
  disable_password_authentication = false

  dynamic "admin_ssh_key" {
    for_each = var.admin_ssh_public_key != null ? [1] : []
    content {
      username   = var.admin_username
      public_key = var.admin_ssh_public_key
    }
  }

  network_interface_ids = [
    azurerm_network_interface.validation.id,
  ]

  os_disk {
    name                 = "${local.vm_name}-osdisk"
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
    disk_size_gb         = 30
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts"
    version   = "latest"
  }

  # System-assigned managed identity for OIDC authentication
  identity {
    type = "SystemAssigned"
  }

  # Boot diagnostics required for Serial Console access
  boot_diagnostics {
    # Uses managed storage account
  }

  custom_data = base64encode(local.cloud_init)

  tags = local.common_tags
}
