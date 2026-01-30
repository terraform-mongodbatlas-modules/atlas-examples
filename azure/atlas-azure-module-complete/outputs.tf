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
