mock_provider "mongodbatlas" {}
mock_provider "aws" {}

variables {
  atlas_org_id         = "org123"
  atlas_project_name   = "test-project"
  atlas_cluster_name   = "test-cluster"
  enable_validation_vm = false
  regions = [
    {
      name       = "US_EAST_1"
      vpc_id     = "vpc-abc123"
      subnet_ids = ["subnet-111", "subnet-222"]
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
    condition     = local.cluster_regions[0].name == "US_EAST_1"
    error_message = "Region name should stay in Atlas format for cluster module"
  }
}

run "single_region_privatelink" {
  command = plan

  assert {
    condition     = length(local.privatelink_endpoints) == 1
    error_message = "Should create one privatelink endpoint"
  }

  assert {
    condition     = local.privatelink_endpoints[0].region == "US_EAST_1"
    error_message = "Privatelink region should match input"
  }
}

run "backup_export_enabled" {
  command = plan

  assert {
    condition     = local.backup_export_config.enabled == true
    error_message = "Backup export should be enabled"
  }

  assert {
    condition     = local.backup_export_config.create_s3_bucket.enabled == true
    error_message = "Module-managed S3 bucket should be enabled"
  }
}

run "vm_region_key_normalized" {
  command = plan

  assert {
    condition     = local.vm_region_key == "us-east-1"
    error_message = "VM region key should normalize Atlas format to AWS format"
  }
}

run "two_regions_even_node_inference" {
  command = plan

  variables {
    regions = [
      {
        name       = "US_EAST_1"
        vpc_id     = "vpc-1"
        subnet_ids = ["subnet-a", "subnet-b"]
      },
      {
        name       = "US_WEST_2"
        vpc_id     = "vpc-2"
        subnet_ids = ["subnet-c", "subnet-d"]
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
        name       = "US_EAST_1"
        vpc_id     = "vpc-1"
        subnet_ids = ["subnet-a"]
      },
      {
        name       = "US_WEST_2"
        vpc_id     = "vpc-2"
        subnet_ids = ["subnet-b"]
      },
      {
        name       = "CENTRAL_US"
        vpc_id     = "vpc-3"
        subnet_ids = ["subnet-c"]
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
        name       = "US_EAST_1"
        vpc_id     = "vpc-1"
        subnet_ids = ["subnet-a"]
        node_count = 5
      }
    ]
  }

  assert {
    condition     = local.cluster_regions[0].node_count == 5
    error_message = "Explicit node_count should override inference"
  }
}

run "empty_regions_rejected" {
  command = plan

  variables {
    regions = []
  }

  expect_failures = [var.regions]
}
