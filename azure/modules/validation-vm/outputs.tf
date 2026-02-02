# VM outputs
# ----------------------------------------------------
output "vm_id" {
  description = "The ID of the validation VM"
  value       = azurerm_linux_virtual_machine.validation.id
}

output "vm_name" {
  description = "The name of the validation VM"
  value       = azurerm_linux_virtual_machine.validation.name
}

output "private_ip_address" {
  description = "The private IP address of the VM"
  value       = azurerm_network_interface.validation.private_ip_address
}

output "admin_username" {
  description = "Admin username for VM login (Serial Console or SSH)"
  value       = var.admin_username
}

output "admin_password" {
  description = "Admin password for VM login via Serial Console"
  value       = random_password.vm_admin.result
  sensitive   = true
}

output "console_access" {
  description = "How to access the VM via Azure Serial Console"
  value       = "Azure Portal → Virtual Machines → ${azurerm_linux_virtual_machine.validation.name} → Help → Serial Console"
}


# Database user outputs
# ----------------------------------------------------
output "database_username" {
  description = "Username of the temporary validation database user"
  value       = mongodbatlas_database_user.validation.username
}

output "database_password" {
  description = "Password of the temporary validation database user"
  value       = random_password.db_user.result
  sensitive   = true
}


# Validation commands (ready to copy-paste)
# ----------------------------------------------------
output "validate_privatelink_command" {
  description = "Run this command on the VM for comprehensive PrivateLink validation (recommended)"
  value       = "./validate-privatelink '${local.connection_string_with_creds}'"
  sensitive   = true
}

output "validate_connection_command" {
  description = "Run this command on the VM to test connectivity with private IP verification"
  value       = "./validate-connection '${local.connection_string_with_creds}'"
  sensitive   = true
}

output "validate_crud_command" {
  description = "Run this command on the VM to test CRUD operations"
  value       = "./validate-crud '${local.connection_string_with_creds}'"
  sensitive   = true
}


# OIDC outputs (for enterprise/manual setup)
# ----------------------------------------------------
output "managed_identity_principal_id" {
  description = "Principal ID of the VM's managed identity. Use for Atlas OIDC database user: <idp_id>/<this_value>"
  value       = azurerm_linux_virtual_machine.validation.identity[0].principal_id
}

output "managed_identity_tenant_id" {
  description = "Tenant ID for Azure AD. Use in Atlas OIDC IdP issuer URL."
  value       = azurerm_linux_virtual_machine.validation.identity[0].tenant_id
}

output "validate_oidc_command" {
  description = "Run this command on the VM for OIDC validation (requires Atlas OIDC setup)"
  value       = "./validate-oidc '${var.atlas_connection_string}'"
}
