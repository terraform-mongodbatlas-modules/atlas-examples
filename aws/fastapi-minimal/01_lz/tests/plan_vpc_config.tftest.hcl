mock_provider "mongodbatlas" {}
mock_provider "aws" {}
mock_provider "local" {}

variables {
  atlas_org_id = "org123"
  cluster_name = "fastapi-minimal"
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
    condition     = length(module.vpc) == 2
    error_message = "Managed path should create one VPC per cluster AWS region"
  }

  assert {
    condition     = local.vpc_cidr_by_region["us-east-1"] == "10.0.0.0/16" && local.vpc_cidr_by_region["us-west-2"] == "10.1.0.0/16"
    error_message = "Managed CIDRs should allocate from base_cidr by declared region order"
  }

  assert {
    condition     = contains(keys(local.privatelink_subnet_ids_by_region), "us-west-2")
    error_message = "PrivateLink subnets should be wired for each cluster AWS region"
  }
}

run "managed_vpc_preserves_declared_region_order" {
  command = plan

  variables {
    regions = [
      { name = "us-west-2", node_count = 2 },
      { name = "us-east-1", node_count = 3 },
    ]
  }

  assert {
    condition     = local.vpc_cidr_by_region["us-west-2"] == "10.0.0.0/16" && local.vpc_cidr_by_region["us-east-1"] == "10.1.0.0/16"
    error_message = "Managed CIDRs should preserve the declared region order so appending regions does not renumber existing VPCs"
  }
}

run "multi_region_cidr_override" {
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
    condition     = local.vpc_cidr_by_region["us-west-2"] == "10.42.0.0/16"
    error_message = "by_region.cidr should override auto allocation for that region"
  }
}

run "managed_vpc_nat_gateway" {
  command = plan

  variables {
    vpc_config = {
      az_count           = 2
      enable_nat_gateway = true
    }
  }

  assert {
    condition     = length(module.vpc["us-east-1"].natgw_ids) == 2
    error_message = "NAT gateway configuration should create one NAT gateway per AZ"
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
    condition     = length(module.vpc) == 0
    error_message = "BYO path should not create managed VPC modules"
  }

  assert {
    condition     = local.privatelink_subnet_ids_by_region["us-west-2"] == tolist(["subnet-west-a", "subnet-west-b"])
    error_message = "BYO by_region should feed PrivateLink subnets per region"
  }
}

run "vpc_managed_az_count_validation" {
  command = plan

  variables {
    vpc_config = {
      az_count = 1.5
    }
  }

  expect_failures = [
    var.vpc_config,
  ]
}

run "vpc_managed_region_az_count_validation" {
  command = plan

  variables {
    vpc_config = {
      by_region = {
        us-east-1 = { az_count = 7 }
      }
    }
  }

  expect_failures = [
    var.vpc_config,
  ]
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

run "vpc_byo_missing_fields" {
  command = plan

  variables {
    vpc_config = {
      create = false
      by_region = {
        us-east-1 = {
          vpc_id = "vpc-byo"
        }
      }
    }
  }

  expect_failures = [
    var.vpc_config,
  ]
}
