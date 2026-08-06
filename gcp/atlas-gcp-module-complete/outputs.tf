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
  value       = local.connection_string
}

output "backup_export" {
  description = "Backup export configuration details"
  value       = module.atlas_gcp.backup_export
}

output "validation_vm" {
  description = "Validation VM details when enabled. Run the validation command on the VM."
  value = var.enable_validation_vm ? {
    instance_id            = module.validation_vm[0].instance_id
    instance_name          = module.validation_vm[0].instance_name
    private_ip             = module.validation_vm[0].private_ip
    zone                   = module.validation_vm[0].zone
    username               = module.validation_vm[0].admin_username
    ssh_command            = module.validation_vm[0].ssh_command
    validation_command     = module.validation_vm[0].validation_command
    iap_firewall_rule_name = module.validation_vm[0].iap_firewall_rule_name
    cloud_router_name      = module.validation_vm[0].cloud_router_name
    cloud_nat_name         = module.validation_vm[0].cloud_nat_name
  } : null
}
