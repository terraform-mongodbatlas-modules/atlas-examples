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

  # To customize or BYO SG, modify the security_group block below.
  privatelink_endpoints = [
    for r in local.regions_with_inferred_node_count : {
      region         = r.name
      subnet_ids     = r.subnet_ids
      security_group = {}
    }
  ]

  # To use an existing bucket, see inline BYO comments in atlas-aws.tf.
  backup_export_config = {
    enabled = true
    create_s3_bucket = {
      enabled = true
    }
  }

  # Validation VM is deployed in the first region.
  # To override, modify the vpc_id / subnet_id in validate-deployment.tf directly.
  validation_vm_vpc_id    = local.regions_with_inferred_node_count[0].vpc_id
  validation_vm_subnet_id = local.regions_with_inferred_node_count[0].subnet_ids[0]
}
