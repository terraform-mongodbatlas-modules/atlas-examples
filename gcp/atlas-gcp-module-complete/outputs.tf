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
  value       = module.atlas_gcp.backup_export
}
