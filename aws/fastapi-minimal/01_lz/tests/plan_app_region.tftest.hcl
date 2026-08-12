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

run "app_region_default" {
  command = plan

  variables {
    ecr_repositories = { api = {} }
    lambda_apps = {
      default = {
        ecr_key     = "api"
        roles       = [{ database_name = "test" }]
        tfvars_path = "../02_app_lambda/infra.auto.tfvars"
      }
    }
  }

  assert {
    condition     = length(aws_security_group.lambda) == 1 && contains(keys(aws_security_group.lambda), "us-east-1")
    error_message = "Default app should create one Lambda SG in regions[0]"
  }

  assert {
    condition     = local.ecr_repositories["api"].region == "us-east-1" && aws_ecr_repository.this["api"].region == "us-east-1"
    error_message = "Default ECR repo should resolve to regions[0]"
  }
}

run "app_region_west" {
  command = plan

  variables {
    regions = [
      { name = "us-east-1", node_count = 3 },
      { name = "us-west-2", node_count = 2 },
    ]
    ecr_repositories = {
      api      = {}
      api-west = { name = "fastapi-minimal-api-west", region = "us-west-2" }
    }
    lambda_apps = {
      default = {
        ecr_key     = "api"
        roles       = [{ database_name = "test" }]
        tfvars_path = "../02_app_lambda/infra.auto.tfvars"
      }
      worker = {
        ecr_key        = "api-west"
        aws_region     = "us-west-2"
        tfvars_path    = "../02_app_worker/infra.auto.tfvars"
        handoff_secret = {}
        roles          = [{ database_name = "jobs" }]
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

  assert {
    condition = length([
      for e in aws_security_group.lambda["us-west-2"].egress : e
      if e.description == "S3 via gateway VPC endpoint (ECR layers)" && length(e.prefix_list_ids) == 1
    ]) == 1
    error_message = "West Lambda SG should include S3 gateway endpoint egress"
  }

  assert {
    condition     = aws_secretsmanager_secret.app["worker"].region == "us-west-2" && aws_secretsmanager_secret_version.app["worker"].region == "us-west-2"
    error_message = "Worker secret and version should use the app region"
  }
}

run "app_region_invalid" {
  command = plan

  variables {
    ecr_repositories = { api = {} }
    lambda_apps = {
      default = {
        ecr_key    = "api"
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
      api = { region = "eu-central-1" }
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
      { name = "us-east-1", node_count = 3 },
      { name = "us-west-2", node_count = 2 },
    ]
    ecr_repositories = {
      api      = {}
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
