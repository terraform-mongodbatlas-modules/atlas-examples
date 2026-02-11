# ---------------------------------------------------------------------------
# Atlas Connectivity Validation VM Module
# ---------------------------------------------------------------------------
# Creates an Azure VM to validate MongoDB Atlas connectivity over PrivateLink.
#
# Features:
#   - Default: Serial Console access (password auth, no public IP)
#   - Optional: SSH via Azure Bastion (when admin_ssh_public_key provided)
#   - Pre-installed mongosh and validation scripts
#   - Validates DNS resolution, connectivity, and CRUD operations
# ---------------------------------------------------------------------------

locals {
  vm_size        = "Standard_B1s"
  admin_username = "azureuser"
  name_prefix    = "atlas"
  vm_name        = "${local.name_prefix}-validation-vm"
  db_username    = "${local.name_prefix}-validation-user"
  common_tags = {
    "Purpose"   = "Atlas Connectivity Validation"
    "ManagedBy" = "Terraform"
  }

  use_bastion        = var.admin_ssh_public_key != null && trimspace(var.admin_ssh_public_key) != ""
  use_serial_console = !local.use_bastion

  # Supports both SRV and standard connection string formats:
  #   - SRV: mongodb+srv://[user:pass@]host/...
  #   - Standard: mongodb://[user:pass@]host1:port,host2:port,host3:port/?replicaSet=...
  is_srv_connection = can(regex("^mongodb\\+srv://", var.atlas_connection_string))

  connection_host = (
    can(regex("@([^/?]+)", var.atlas_connection_string))
    ? regex("@([^/?]+)", var.atlas_connection_string)[0]
    : regex("^mongodb(?:\\+srv)?://([^@/?]+)", var.atlas_connection_string)[0]
  )

  connection_string_with_creds = local.is_srv_connection ? (
    "mongodb+srv://${mongodbatlas_database_user.validation.username}:${random_password.db_user.result}@${local.connection_host}"
    ) : (
    "mongodb://${mongodbatlas_database_user.validation.username}:${random_password.db_user.result}@${local.connection_host}/?${regex("\\?(.+)$", var.atlas_connection_string)[0]}"
  )

  shared_scripts_path = "${path.module}/../../../shared/validation-vm"
  validate_script     = file("${local.shared_scripts_path}/validate-atlas.sh")

  cloud_init = templatefile("${local.shared_scripts_path}/cloud-init.yaml.tftpl", {
    admin_username    = local.admin_username
    validate_script   = local.validate_script
    connection_string = local.connection_string_with_creds
  })

  # ---------------------------------------------------------------------------
  # VNet extraction for Bastion subnet
  # ---------------------------------------------------------------------------
  # Extract VNet ID from subnet_id to create AzureBastionSubnet in same VNet
  # Subnet ID format: /subscriptions/.../virtualNetworks/{vnet}/subnets/{subnet}
  # ---------------------------------------------------------------------------
  vnet_id = join("/", slice(split("/", var.subnet_id), 0, 9))
}
resource "random_password" "db_user" {
  length  = 24
  special = false
}

# For Serial Console access (when not using Bastion)
resource "random_password" "vm_admin" {
  count = local.use_serial_console ? 1 : 0

  length      = 24
  special     = false
  min_lower   = 1
  min_upper   = 1
  min_numeric = 1
}

# Temporary Database User (for SCRAM authentication)
resource "mongodbatlas_database_user" "validation" {
  project_id         = var.atlas_project_id
  username           = local.db_username
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
  size                = local.vm_size

  admin_username = local.admin_username

  # Authentication mode depends on access method
  disable_password_authentication = local.use_bastion

  # For Serial Console (when not using Bastion)
  admin_password = local.use_serial_console ? random_password.vm_admin[0].result : null

  # Bastion: SSH key authentication
  dynamic "admin_ssh_key" {
    for_each = local.use_bastion ? [1] : []
    content {
      username   = local.admin_username
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

  # Boot diagnostics required for Serial Console
  boot_diagnostics {
    # Uses managed storage account
  }

  custom_data = base64encode(local.cloud_init)

  tags = local.common_tags
}

# ---------------------------------------------------------------------------
# Azure Bastion Resources (conditional - only when SSH key is provided)
# ---------------------------------------------------------------------------
# Creates Standard SKU Bastion for native SSH client support.
# Requires an AzureBastionSubnet in the same VNet as the VM.
# ---------------------------------------------------------------------------

# Public IP for Azure Bastion
resource "azurerm_public_ip" "bastion" {
  count = local.use_bastion ? 1 : 0

  name                = "${local.name_prefix}-bastion-pip"
  location            = var.location
  resource_group_name = var.resource_group_name
  allocation_method   = "Static"
  sku                 = "Standard"

  tags = local.common_tags
}

# AzureBastionSubnet in the same VNet as the VM
# Must be named exactly "AzureBastionSubnet" and have at least /26 CIDR
resource "azurerm_subnet" "bastion" {
  count = local.use_bastion ? 1 : 0

  name                 = "AzureBastionSubnet"
  resource_group_name  = var.resource_group_name
  virtual_network_name = element(split("/", local.vnet_id), length(split("/", local.vnet_id)) - 1)
  address_prefixes     = [var.bastion_subnet_cidr]

  # Note: Azure requires a /26 or larger range for Bastion.
}

# Azure Bastion Host (Standard SKU for native SSH client support)
resource "azurerm_bastion_host" "bastion" {
  count = local.use_bastion ? 1 : 0

  name                = "${local.name_prefix}-bastion"
  location            = var.location
  resource_group_name = var.resource_group_name
  sku                 = "Standard"

  # Enable native client support for SSH from local terminal
  tunneling_enabled = true

  ip_configuration {
    name                 = "configuration"
    subnet_id            = azurerm_subnet.bastion[0].id
    public_ip_address_id = azurerm_public_ip.bastion[0].id
  }

  tags = local.common_tags
}
