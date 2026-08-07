mock_provider "mongodbatlas" {}
mock_provider "aws" {}
mock_provider "local" {}

variables {
  atlas_org_id = "org123"
}

run "regions_aws_style" {
  command = plan

  variables {
    regions = [{ name = "us-east-1" }]
  }

  assert {
    condition     = local.aws_region == "us-east-1" && local.cluster_regions[0].name == "US_EAST_1"
    error_message = "AWS-style regions[].name should normalize to AWS keys and Atlas cluster input"
  }

  assert {
    condition     = length(module.vpc) == 1 && contains(keys(module.vpc), "us-east-1")
    error_message = "VPC module should be keyed by normalized AWS region"
  }
}

run "regions_atlas_style" {
  command = plan

  variables {
    regions = [{ name = "US_EAST_1" }]
  }

  assert {
    condition     = local.aws_region == "us-east-1" && local.cluster_regions[0].name == "US_EAST_1"
    error_message = "Atlas-format regions[].name should normalize to AWS keys internally"
  }
}

run "regions_mixed_multi" {
  command = plan

  variables {
    regions = [
      { name = "us-east-1" },
      { name = "us-west-2" },
    ]
  }

  assert {
    condition     = length(module.vpc) == 2 && contains(keys(module.vpc), "us-west-2")
    error_message = "Multi-region should create one VPC per AWS region"
  }
}

run "regions_duplicate_mixed" {
  command = plan

  variables {
    regions = [
      { name = "US_EAST_1" },
      { name = "us-east-1" },
    ]
  }

  expect_failures = [
    var.regions,
  ]
}

run "regions_invalid_format" {
  command = plan

  variables {
    regions = [{ name = "not-a-region" }]
  }

  expect_failures = [
    var.regions,
  ]
}
