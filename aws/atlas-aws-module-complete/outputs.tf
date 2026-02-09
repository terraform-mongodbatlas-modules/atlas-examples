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
  value       = module.atlas_aws.backup_export
}

# ---------------------------------------------------------------------------
# Validation VM
# ---------------------------------------------------------------------------
output "validation_vm" {
  description = "Validation VM details (if enabled). Run ./validate-atlas on the VM."
  value = var.enable_validation_vm ? {
    instance_id = module.validation_vm[0].instance_id
    username    = module.validation_vm[0].admin_username
    access = {
      ec2_instance_connect = module.validation_vm[0].ssh_command
      ssm_session_manager  = "${module.validation_vm[0].ssm_command}  # Then run: sudo su - ${module.validation_vm[0].admin_username}"
    }
  } : null
}
