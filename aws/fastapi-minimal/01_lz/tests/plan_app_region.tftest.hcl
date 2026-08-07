mock_provider "mongodbatlas" {}
mock_provider "aws" {}
mock_provider "local" {}

variables {
  atlas_org_id = "org123"
}

run "app_region_default" {
  command = plan

  assert {
    condition     = length(aws_security_group.lambda) == 1 && contains(keys(aws_security_group.lambda), "us-east-1")
    error_message = "Default app should create one Lambda SG in regions[0]"
  }

  assert {
    condition     = local.ecr_repositories["default"].region == "us-east-1" && aws_ecr_repository.this["default"].region == "us-east-1"
    error_message = "Default ECR repo should resolve to regions[0]"
  }
}

run "app_region_west" {
  command = plan

  variables {
    regions = [
      { name = "US_EAST_1", node_count = 3 },
      { name = "US_WEST_2", node_count = 2 },
    ]
    ecr_repositories = {
      default  = {}
      api-west = { name = "fastapi-minimal-api-west", region = "us-west-2" }
    }
    lambda_apps = {
      default = {
        ecr_key     = "default"
        roles       = [{ database_name = "test" }]
        tfvars_path = "../02_app_lambda/infra.auto.tfvars"
      }
      worker = {
        ecr_key     = "api-west"
        aws_region  = "us-west-2"
        tfvars_path = "../02_app_worker/infra.auto.tfvars"
        roles       = [{ database_name = "jobs" }]
      }
    }
  }

  assert {
    condition     = length(aws_security_group.lambda) == 2
    error_message = "Apps in two regions should create two Lambda SGs"
  }

  assert {
    condition     = local.app_handoff_payloads["worker"].aws_region == "us-west-2"
    error_message = "Worker handoff should target us-west-2"
  }

  assert {
    condition     = local.ecr_repositories["api-west"].region == "us-west-2"
    error_message = "West ECR repo should resolve to us-west-2"
  }
}

run "app_region_invalid" {
  command = plan

  variables {
    lambda_apps = {
      default = {
        ecr_key    = "default"
        aws_region = "eu-central-1"
        roles      = [{ database_name = "test" }]
      }
    }
  }

  expect_failures = [
    var.lambda_apps,
  ]
}

run "ecr_region_invalid" {
  command = plan

  variables {
    ecr_repositories = {
      default = { region = "eu-central-1" }
    }
  }

  expect_failures = [
    var.ecr_repositories,
  ]
}

run "app_ecr_region_mismatch" {
  command = plan

  variables {
    regions = [
      { name = "US_EAST_1", node_count = 3 },
      { name = "US_WEST_2", node_count = 2 },
    ]
    ecr_repositories = {
      default  = {}
      api-west = { region = "us-west-2" }
    }
    lambda_apps = {
      default = {
        ecr_key = "api-west"
        roles   = [{ database_name = "test" }]
      }
    }
  }

  expect_failures = [
    var.lambda_apps,
  ]
}
