# Prerequisite networking for the Azure example's E2E runs — NOT a copy of the
# example. See e2e/network-bootstrap/README.md for why this exists and how to
# keep it in sync with the example's inputs.
resource "azurerm_resource_group" "this" {
  name     = "atlas-examples-e2e-${var.name_suffix}"
  location = var.azure_location
}

resource "azurerm_virtual_network" "this" {
  name                = "atlas-examples-e2e-vnet-${var.name_suffix}"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  address_space       = ["10.0.0.0/16"]
}

resource "azurerm_subnet" "private_endpoint" {
  name                 = "atlas-pe-subnet"
  resource_group_name  = azurerm_resource_group.this.name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = ["10.0.1.0/24"]
}
