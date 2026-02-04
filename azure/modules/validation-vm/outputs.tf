# ---------------------------------------------------------------------------
# Validation VM Outputs
# ---------------------------------------------------------------------------

output "vm_name" {
  description = "VM name for Azure Portal navigation"
  value       = azurerm_linux_virtual_machine.validation.name
}

output "admin_username" {
  description = "Username for VM login"
  value       = local.admin_username
}

output "admin_password" {
  description = "Password for Serial Console login (default access mode)"
  value       = local.use_serial_console ? random_password.vm_admin[0].result : null
  sensitive   = true
}

output "access" {
  description = "How to access the VM"
  value       = local.use_bastion ? "SSH via Azure Bastion" : "Azure Portal → VM → Serial Console"
}
