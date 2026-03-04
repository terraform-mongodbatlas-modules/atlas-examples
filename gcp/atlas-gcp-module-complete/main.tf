locals {
  region_count = length(var.regions)
  gcp_to_atlas = { for k, v in var.atlas_to_gcp_region : v => k }

  # Normalize region name to Atlas format (cluster module requires it).
  # Accepts either "US_EAST_4" (pass-through) or "us-east4" (looked up).
  regions_normalized = [
    for r in var.regions : merge(r, {
      atlas_region = lookup(local.gcp_to_atlas, r.name, r.name)
    })
  ]

  # Infer electable node_count per region (per shard) if not provided.
  # Atlas interprets this as "nodes per shard in that region".
  # Non-first regions always get 1 node. First region:
  #   - single region  -> 3 (HA)
  #   - even R         -> 2 (need odd total)
  #   - odd R >= 3     -> 1
  regions_with_inferred_node_count = [
    for i, r in local.regions_normalized : merge(r, {
      node_count = coalesce(
        try(r.node_count, null),
        i > 0 ? 1 :
        local.region_count == 1 ? 3 :
        local.region_count % 2 == 0 ? 2 : 1
      )
    })
  ]

  cluster_regions = [
    for r in local.regions_with_inferred_node_count : {
      name       = r.atlas_region
      node_count = r.node_count
    }
  ]

  privatelink_endpoints = [
    for r in local.regions_with_inferred_node_count : {
      region     = r.name
      subnetwork = r.subnetwork
    }
  ]

  backup_export_config = {
    enabled = true
    create_bucket = {
      enabled       = true
      location      = local.regions_normalized[0].name
      force_destroy = var.backup_export_force_destroy
    }
  }
}
