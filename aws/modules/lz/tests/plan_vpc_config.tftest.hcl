mock_provider "mongodbatlas" {}
mock_provider "aws" {
  mock_data "aws_availability_zones" {
    defaults = { names = ["us-east-1a", "us-east-1b", "us-east-1c", "us-east-1d", "us-east-1e", "us-east-1f"] }
  }
  mock_data "aws_caller_identity" {
    defaults = { account_id = "123456789012" }
  }
}
mock_provider "random" {
  override_during = plan
  mock_resource "random_password" {
    defaults = { result = "test-password" }
  }
}

override_module {
  target          = module.atlas_cluster
  override_during = plan
  outputs = {
    cluster_name = "hybridrag-ui"
    state_name   = "IDLE"
    connection_strings = {
      standard_srv = "mongodb+srv://cluster.example.mongodb.net"
      private_srv  = ""
      private_endpoint = [{
        srv_connection_string = "mongodb+srv://pl-0.example.mongodb.net"
        endpoints             = []
      }]
    }
  }
}

variables {
  atlas_org_id = "org123"
  cluster_name = "hybridrag-ui"
}

run "multi_region_auto_vpc" {
  command = plan

  variables {
    regions = [
      { name = "us-east-1", node_count = 3 },
      { name = "us-west-2", node_count = 2 },
    ]
  }

  assert {
    condition = alltrue([
      length(module.vpc) == 2,
      local.vpc_cidr_by_region["us-east-1"] == "10.0.0.0/16",
      local.vpc_cidr_by_region["us-west-2"] == "10.1.0.0/16",
    ])
    error_message = "Managed path should create one VPC per cluster AWS region with sequential CIDRs"
  }
}

run "vpc_byo_all_regions" {
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
    condition = alltrue([
      length(module.vpc) == 0,
      local.privatelink_subnet_ids_by_region["us-west-2"] == tolist(["subnet-west-a", "subnet-west-b"]),
    ])
    error_message = "BYO path should not create managed VPC modules and should feed PrivateLink subnets"
  }
}

run "vpc_managed_rejects_byo_fields" {
  command = plan

  variables {
    vpc_config = {
      by_region = {
        us-east-1 = {
          vpc_id = "vpc-should-fail"
        }
      }
    }
  }

  expect_failures = [
    var.vpc_config,
  ]
}

run "vpc_byo_missing_region" {
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
          private_subnet_ids      = ["subnet-east-a"]
          vpc_cidr_block          = "10.0.0.0/16"
          private_route_table_ids = ["rtb-east"]
        }
      }
    }
  }

  expect_failures = [
    var.vpc_config,
  ]
}
