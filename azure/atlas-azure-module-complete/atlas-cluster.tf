module "atlas_cluster" {
  source  = "terraform-mongodbatlas-modules/cluster/mongodbatlas"
  version = "~> 0.3.0"

  project_id = module.atlas_project.id
  name       = var.atlas_cluster_name

  provider_name = "AZURE"
  cluster_type  = "SHARDED"
  shard_count   = 2

  regions = local.cluster_regions

  encryption_at_rest_provider = "NONE"

  tags = var.tags

  depends_on = [module.atlas_project, module.atlas_azure]
}
