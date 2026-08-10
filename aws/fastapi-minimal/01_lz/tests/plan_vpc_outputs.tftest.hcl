mock_provider "mongodbatlas" {}
mock_provider "aws" {
  mock_data "aws_availability_zones" {
    defaults = { names = ["us-east-1a", "us-east-1b", "us-east-1c", "us-east-1d", "us-east-1e", "us-east-1f"] }
  }
}
mock_provider "local" {}

variables {
  atlas_org_id = "org123"
  cluster_name = "fastapi-minimal"
}

run "operations_vpc_pin_single_region" {
  command = plan

  assert {
    condition     = output.operations.vpc_pin["us-east-1"].cidr == "10.0.0.0/16" && output.operations.vpc_pin["us-east-1"].az_count == 2
    error_message = "Single-region managed VPC should expose pin CIDR and az_count"
  }
}

run "operations_vpc_pin_pinned" {
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
    condition     = output.operations.vpc_pin["us-west-2"].cidr == "10.42.0.0/16"
    error_message = "Pinned CIDR should appear in vpc_pin"
  }
}

run "operations_regions_order" {
  command = plan

  variables {
    regions = [
      { name = "us-west-2", node_count = 2 },
      { name = "us-east-1", node_count = 3 },
    ]
  }

  assert {
    condition     = output.operations.regions[0].aws_region == "us-west-2"
    error_message = "regions[0] should follow declared region order"
  }
}

run "operations_vpc_pin_null_byo" {
  command = plan

  variables {
    regions = [
      { name = "us-east-1", node_count = 3 },
      { name = "us-west-2", node_count = 2 },
    ]
    vpc_config = {
      create = false
      by_region = {
        us-east-1 = {
          vpc_id                  = "vpc-east"
          private_subnet_ids      = ["subnet-east-a", "subnet-east-b"]
          vpc_cidr_block          = "10.0.0.0/16"
          private_route_table_ids = ["rtb-east"]
        }
        us-west-2 = {
          vpc_id                  = "vpc-west"
          private_subnet_ids      = ["subnet-west-a", "subnet-west-b"]
          vpc_cidr_block          = "10.1.0.0/16"
          private_route_table_ids = ["rtb-west"]
        }
      }
    }
  }

  assert {
    condition     = output.operations.vpc_pin == null
    error_message = "BYO path should not expose vpc_pin"
  }
}

run "aws_vpcs_byo" {
  command = plan

  variables {
    regions = [
      { name = "us-east-1", node_count = 3 },
      { name = "us-west-2", node_count = 2 },
    ]
    vpc_config = {
      create = false
      by_region = {
        us-east-1 = {
          vpc_id                  = "vpc-east"
          private_subnet_ids      = ["subnet-east-a", "subnet-east-b"]
          vpc_cidr_block          = "10.0.0.0/16"
          private_route_table_ids = ["rtb-east"]
        }
        us-west-2 = {
          vpc_id                  = "vpc-west"
          private_subnet_ids      = ["subnet-west-a", "subnet-west-b"]
          vpc_cidr_block          = "10.1.0.0/16"
          private_route_table_ids = ["rtb-west"]
        }
      }
    }
  }

  assert {
    condition     = output.aws.vpcs["us-east-1"].vpc_id == "vpc-east" && output.aws.vpcs["us-west-2"].vpc_id == "vpc-west"
    error_message = "BYO path should echo vpc IDs in aws.vpcs"
  }
}
