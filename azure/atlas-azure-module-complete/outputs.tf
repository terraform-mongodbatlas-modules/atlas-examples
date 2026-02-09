output "project_id" {
  description = "MongoDB Atlas project ID."
  value       = module.atlas_project.id
}

output "cluster_id" {
  description = "Unique 24-hexadecimal digit string that identifies the cluster."
  value       = module.atlas_cluster.cluster_id
}

output "connection_string" {
  description = "Private endpoint SRV connection string (uses first region for sharded clusters)"
  value = coalesce(
    try(module.atlas_cluster.connection_strings.private_endpoint[0].srv_connection_string, ""),
    try(module.atlas_cluster.connection_strings.private_srv, ""),
    module.atlas_cluster.connection_strings.standard_srv
  )
}

output "backup_export" {
  description = "Backup export configuration details"
  value       = module.atlas_azure.backup_export
}

# ---------------------------------------------------------------------------
# Validation VM
# ---------------------------------------------------------------------------
output "validation_vm" {
  description = "Validation VM details (if enabled). Run ./validate-atlas on the VM."
  value = var.enable_validation_vm ? {
    vm_name  = module.validation_vm[0].vm_name
    username = module.validation_vm[0].admin_username
    access   = module.validation_vm[0].access
  } : null
}

output "validation_vm_password" {
  description = "VM password for Serial Console login (use with username from validation_vm output)"
  value       = var.enable_validation_vm ? module.validation_vm[0].admin_password : null
  sensitive   = true
}
