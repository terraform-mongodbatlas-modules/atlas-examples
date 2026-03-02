mock_provider "mongodbatlas" {}
mock_provider "google" {}

variables {
  gcp_project_id     = "test-project"
  atlas_org_id       = "org123"
  atlas_project_name = "test-project"
  atlas_cluster_name = "test-cluster"
  regions = [
    {
      name       = "US_EAST_4"
      subnetwork = "projects/test/regions/us-east4/subnetworks/default"
    }
  ]
}

run "single_region_infers_3_nodes" {
  command = plan

  assert {
    condition     = local.cluster_regions[0].node_count == 3
    error_message = "Single region should infer 3 nodes"
  }

  assert {
    condition     = local.cluster_regions[0].name == "US_EAST_4"
    error_message = "Region name should be preserved"
  }
}

run "single_region_privatelink" {
  command = plan

  assert {
    condition     = length(local.privatelink_endpoints) == 1
    error_message = "Should create one privatelink endpoint"
  }

  assert {
    condition     = local.privatelink_endpoints[0].region == "US_EAST_4"
    error_message = "Privatelink region should match input"
  }

  assert {
    condition     = local.privatelink_endpoints[0].subnetwork == "projects/test/regions/us-east4/subnetworks/default"
    error_message = "Privatelink subnetwork should match input"
  }
}

run "backup_uses_first_region" {
  command = plan

  assert {
    condition     = local.backup_export_config.enabled == true
    error_message = "Backup should be enabled"
  }

  assert {
    condition     = local.backup_export_config.create_bucket.location == "US_EAST_4"
    error_message = "Backup location should use first region"
  }
}

run "two_regions_even_node_inference" {
  command = plan

  variables {
    regions = [
      {
        name       = "US_EAST_4"
        subnetwork = "projects/test/regions/us-east4/subnetworks/default"
      },
      {
        name       = "US_WEST_2"
        subnetwork = "projects/test/regions/us-west2/subnetworks/default"
      }
    ]
  }

  assert {
    condition     = local.cluster_regions[0].node_count == 2
    error_message = "First region of even count should get 2 nodes"
  }

  assert {
    condition     = local.cluster_regions[1].node_count == 1
    error_message = "Second region of even count should get 1 node"
  }
}

run "three_regions_odd_node_inference" {
  command = plan

  variables {
    regions = [
      {
        name       = "US_EAST_4"
        subnetwork = "projects/test/regions/us-east4/subnetworks/a"
      },
      {
        name       = "US_WEST_2"
        subnetwork = "projects/test/regions/us-west2/subnetworks/b"
      },
      {
        name       = "CENTRAL_US"
        subnetwork = "projects/test/regions/us-central1/subnetworks/c"
      }
    ]
  }

  assert {
    condition     = local.cluster_regions[0].node_count == 1
    error_message = "Odd region count should infer 1 node each"
  }

  assert {
    condition     = local.cluster_regions[1].node_count == 1
    error_message = "Odd region count should infer 1 node each"
  }

  assert {
    condition     = local.cluster_regions[2].node_count == 1
    error_message = "Odd region count should infer 1 node each"
  }
}

run "explicit_node_count_override" {
  command = plan

  variables {
    regions = [
      {
        name       = "US_EAST_4"
        subnetwork = "projects/test/regions/us-east4/subnetworks/default"
        node_count = 5
      }
    ]
  }

  assert {
    condition     = local.cluster_regions[0].node_count == 5
    error_message = "Explicit node_count should override inference"
  }
}

run "tags_default_empty" {
  command = plan

  assert {
    condition     = length(var.tags) == 0
    error_message = "Tags should default to empty map"
  }
}

run "empty_regions_rejected" {
  command = plan

  variables {
    regions = []
  }

  expect_failures = [var.regions]
}
