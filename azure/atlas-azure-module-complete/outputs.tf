output "project_id" {
  description = "MongoDB Atlas project ID."
  value       = module.atlas_project.id
}

output "cluster_id" {
  description = "Unique 24-hexadecimal digit string that identifies the cluster."
  value       = module.atlas_cluster.cluster_id
}

output "connection_string_private_srv" {
  description = "Private endpoint SRV connection string"
  value       = module.atlas_cluster.connection_strings.private_srv
}

output "connection_string_private_endpoint" {
  description = "Private endpoint connection strings by region"
  value       = module.atlas_cluster.connection_strings.private_endpoint
}

output "connection_string_standard_srv" {
  description = "Standard SRV connection string"
  value       = module.atlas_cluster.connection_strings.standard_srv
}

output "backup_export" {
  description = "Backup export configuration details"
  value       = module.atlas_azure.backup_export
}

output "validation_vm" {
  description = "Validation VM details (if enabled)"
  value = var.enable_validation_vm ? {
    vm_name                      = module.validation_vm[0].vm_name
    private_ip                   = module.validation_vm[0].private_ip_address
    admin_username               = module.validation_vm[0].admin_username
    admin_password               = module.validation_vm[0].admin_password
    console_access               = module.validation_vm[0].console_access
    database_username            = module.validation_vm[0].database_username
    validate_privatelink_command = module.validation_vm[0].validate_privatelink_command
    validate_connection_command  = module.validation_vm[0].validate_connection_command
    validate_crud_command        = module.validation_vm[0].validate_crud_command
  } : null
  sensitive = true
}
