locals {
  region_count = length(var.regions)

  # Infer electable node_count per region (per shard) if not provided:
  # - 1 region  -> 3
  # - odd R>=3  -> 1 each
  # - even R    -> 2 in first region, 1 in the rest
  #
  # Atlas interprets this as "nodes per shard in that region".
  regions_with_inferred_node_count = [
    for i, r in var.regions : merge(r, {
      node_count = coalesce(
        try(r.node_count, null),
        local.region_count == 1 ? 3 :
        local.region_count % 2 == 1 ? 1 :
        (i == 0 ? 2 : 1)
      )
    })
  ]

  cluster_regions = [
    for r in local.regions_with_inferred_node_count : {
      name       = r.name
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
      enabled  = true
      location = var.regions[0].name
    }
  }
}
