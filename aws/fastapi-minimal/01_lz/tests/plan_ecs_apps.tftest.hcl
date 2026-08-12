mock_provider "mongodbatlas" {
  override_during = plan
}
mock_provider "aws" {
  override_during = plan
  mock_data "aws_availability_zones" {
    defaults = { names = ["us-east-1a", "us-east-1b", "us-east-1c", "us-east-1d", "us-east-1e", "us-east-1f"] }
  }
}
mock_provider "local" {}

override_module {
  target          = module.atlas_cluster
  override_during = plan
  outputs = {
    cluster_name = "fastapi-minimal"
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
  cluster_name = "fastapi-minimal"
}

run "ecs_fastapi_path" {
  command = plan

  variables {
    ecr_repositories = { api = {} }
    http_edges       = { main = {} }
    ecs_apps = {
      api = {
        ecr_key     = "api"
        routing     = { edge = "main", path_pattern = ["/*"], listener_priority = 100 }
        roles       = [{ database_name = "test" }]
        tfvars_path = "../02_app_ecs/infra.auto.tfvars"
      }
    }
  }

  assert {
    condition = alltrue([
      length(aws_iam_role.ecs_task) == 1,
      length(aws_iam_role.ecs_task_execution) == 1,
      length(mongodbatlas_database_user.ecs) == 1,
      length(local_file.ecs_app_tfvars) == 1,
      length(module.vpc["us-east-1"].public_subnets) == 2,
      length(module.http_edge) == 1,
    ])
    error_message = "ECS path should create IAM, DB user, handoff, public subnets, and HTTP edge"
  }

  assert {
    condition     = local_file.ecs_app_tfvars["api"].filename == "../02_app_ecs/infra.auto.tfvars"
    error_message = "Handoff path should target 02_app_ecs"
  }
}

run "ecs_lz_only_no_public_edge" {
  command = plan

  assert {
    condition = alltrue([
      length(aws_iam_role.ecs_task) == 0,
      length(module.vpc["us-east-1"].public_subnets) == 0,
    ])
    error_message = "Platform-only defaults should not create ECS resources or public subnets"
  }
}

run "lambda_and_ecs_shared_region" {
  command = plan

  variables {
    ecr_repositories = { api = {} }
    lambda_apps = {
      api = {
        ecr_key     = "api"
        roles       = [{ database_name = "test" }]
        tfvars_path = "../02_app_lambda/infra.auto.tfvars"
      }
    }
    ecs_apps = {
      web = {
        ecr_key     = "api"
        roles       = [{ database_name = "test" }]
        tfvars_path = "../02_app_ecs/infra.auto.tfvars"
      }
    }
  }

  assert {
    condition = alltrue([
      length(aws_security_group.lambda) == 1,
      length(aws_vpc_endpoint.interface) == 4,
      length(aws_vpc_endpoint.s3) == 1,
    ])
    error_message = "Lambda and ECS in one region should share one SG and one endpoint set"
  }
}

run "ecs_ecr_key_missing" {
  command = plan

  variables {
    ecr_repositories = { api = {} }
    ecs_apps = {
      api = {
        ecr_key = "missing"
        roles   = [{ database_name = "test" }]
      }
    }
  }

  expect_failures = [
    var.ecs_apps,
  ]
}
