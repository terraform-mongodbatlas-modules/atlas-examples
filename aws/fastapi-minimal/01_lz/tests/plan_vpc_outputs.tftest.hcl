mock_provider "mongodbatlas" {}
mock_provider "aws" {}
mock_provider "local" {}

variables {
  atlas_org_id = "org123"
}

run "operations_vpc_config_single_region" {
  command = plan

  assert {
    condition     = output.operations.vpc_config_resolved.by_region["us-east-1"].cidr == "10.0.0.0/16"
    error_message = "Single-region managed VPC should get first index CIDR"
  }
}

run "operations_vpc_config_pinned" {
  command = plan

  variables {
    regions = [
      { name = "us-east-1", node_count = 3 },
      { name = "us-west-2", node_count = 2 },
    ]
    vpc_config = {
      by_region = {
        us-west-2 = { cidr = "10.42.0.0/16" }
      }
    }
  }

  assert {
    condition     = output.operations.vpc_config_resolved.by_region["us-west-2"].cidr == "10.42.0.0/16"
    error_message = "Pinned CIDR should appear in operations output"
  }
}

run "operations_regions_primary" {
  command = plan

  variables {
    regions = [
      { name = "us-west-2", node_count = 2 },
      { name = "us-east-1", node_count = 3 },
    ]
  }

  assert {
    condition     = output.operations.regions_resolved[0].primary == true && output.operations.regions_resolved[0].aws_region == "us-west-2"
    error_message = "regions[0] should be marked primary in operations output"
  }
}
