output "resource_group_name" {
  description = "Name of the resource group created for the E2E run"
  value       = azurerm_resource_group.this.name
}

output "subnet_id" {
  description = "Full resource ID of the private endpoint subnet"
  value       = azurerm_subnet.private_endpoint.id
}

output "azure_location" {
  description = "Azure location of the networking resources"
  value       = azurerm_resource_group.this.location
}

output "regions" {
  description = "Ready-to-consume value for the example's regions variable"
  value = [{
    name           = var.atlas_region
    azure_location = azurerm_resource_group.this.location
    subnet_id      = azurerm_subnet.private_endpoint.id
  }]
}
