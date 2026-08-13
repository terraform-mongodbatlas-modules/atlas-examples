output "index_run" {
  description = "Locator for just index-create (region, cluster, service)."
  value       = module.ecs_service.index_run
}

output "ecs_cluster_name" {
  value = module.ecs_service.ecs_cluster_name
}

output "ecs_service_name" {
  value = module.ecs_service.ecs_service_name
}
