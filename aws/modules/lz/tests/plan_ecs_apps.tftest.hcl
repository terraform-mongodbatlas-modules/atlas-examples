mock_provider "mongodbatlas" {
  override_during = plan
}

mock_provider "aws" {
  override_during = plan

  mock_data "aws_availability_zones" {
    defaults = { names = ["us-east-1a", "us-east-1b", "us-east-1c", "us-east-1d", "us-east-1e", "us-east-1f"] }
  }

  mock_data "aws_caller_identity" {
    defaults = { account_id = "123456789012" }
  }

  mock_data "aws_ec2_managed_prefix_list" {
    defaults = { id = "pl-cloudfront" }
  }

  mock_data "aws_cloudfront_cache_policy" {
    defaults = { id = "cache-disabled" }
  }

  mock_data "aws_cloudfront_origin_request_policy" {
    defaults = { id = "origin-req" }
  }
}

mock_provider "random" {
  override_during = plan

  mock_resource "random_password" {
    defaults = { result = "test-origin-header-value-32chars" }
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

run "ecs_ui_path" {
  command = plan

  variables {
    ecr_repositories = { ui = {} }
    http_edges       = { main = {} }
    ecs_apps = {
      ui = {
        name            = "hybridrag-ui"
        ecr_key         = "ui"
        internet_egress = true
        routing = {
          edge              = "main"
          path_pattern      = ["/*"]
          listener_priority = 100
          container_port    = 8001
        }
        roles = [{ database_name = "hybridrag" }]
      }
    }
  }

  assert {
    condition = alltrue([
      length(aws_iam_role.ecs_task) == 1,
      length(aws_iam_role.ecs_task_execution) == 1,
      length(mongodbatlas_database_user.ecs) == 1,
      length(module.http_edge) == 1,
      length(aws_security_group.app) == 1,
      output.ecs_apps["ui"].name == "hybridrag-ui",
      output.ecs_apps["ui"].runtime_secret_name == "hybridrag-ui-app",
      output.ecs_apps["ui"].routing.container_port == 8001,
      !contains(keys(output.ecs_apps["ui"].routing), "health_check_path"),
      !contains(keys(output.ecs_apps["ui"]), "task_cpu"),
      !contains(keys(output.ecs_apps["ui"]), "handoff_secret_name"),
      output.ecs_apps["ui"].routing.origin_header_name == "X-Origin-Verify",
      output.ecs_apps["ui"].mongo.database_name == "hybridrag",
      !contains(keys(output.ecs_apps["ui"]), "ecs_cluster_arn"),
      !contains(keys(output.ecs_apps["ui"]), "container_env_vars"),
      contains(keys(nonsensitive(output.http_edge_origin_header_values)), "main"),
      module.http_edge["main"].origin_header_name == "X-Origin-Verify",
      strcontains(
        jsondecode(aws_iam_role_policy.ecs_task_execution_secrets["ui"].policy).Statement[0].Resource,
        "secret:hybridrag-ui-app-*"
      ),
    ])
    error_message = "ECS UI path should create IAM, DB user, HTTP edge, name-glob secrets IAM, and typed ecs_apps without ecs_cluster or container_env_vars"
  }
}

run "lz_only_no_public_edge" {
  command = plan

  assert {
    condition = alltrue([
      length(aws_iam_role.ecs_task) == 0,
      length(module.vpc["us-east-1"].public_subnets) == 0,
    ])
    error_message = "Platform-only defaults should not create ECS resources or public subnets"
  }
}

run "ecs_ecr_key_missing" {
  command = plan

  variables {
    ecr_repositories = { ui = {} }
    ecs_apps = {
      ui = {
        ecr_key = "missing"
        roles   = [{ database_name = "hybridrag" }]
      }
    }
  }

  expect_failures = [
    var.ecs_apps,
  ]
}

run "ecs_routing_requires_path_or_host" {
  command = plan

  variables {
    ecr_repositories = { ui = {} }
    http_edges       = { main = {} }
    ecs_apps = {
      ui = {
        ecr_key = "ui"
        routing = {
          edge              = "main"
          listener_priority = 100
        }
        roles = [{ database_name = "hybridrag" }]
      }
    }
  }

  expect_failures = [
    var.ecs_apps,
  ]
}

