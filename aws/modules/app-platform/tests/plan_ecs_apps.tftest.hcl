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

  mock_resource "aws_cloudfront_distribution" {
    defaults = {
      domain_name = "d111111abcdef8.cloudfront.net"
      id          = "E123456789"
    }
  }
}

mock_provider "random" {
  override_during = plan

  mock_resource "random_password" {
    defaults = { result = "test-origin-header-value-32chars" }
  }
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
      length(module.http_edge) == 1,
      length(aws_security_group.app) == 1,
      output.ecs_apps["ui"].name == "hybridrag-ui",
      output.ecs_apps["ui"].runtime_secret_name == "hybridrag-ui-app",
      output.ecs_apps["ui"].routing.container_port == 8001,
      output.ecs_apps["ui"].mongo.database_name == "hybridrag",
      !contains(keys(output.ecs_apps["ui"].routing), "health_check_path"),
      !contains(keys(output.ecs_apps["ui"]), "task_cpu"),
      !contains(keys(output.ecs_apps["ui"]), "ecs_cluster_arn"),
      output.ecs_apps["ui"].routing.origin_header_name == "X-Origin-Verify",
      contains(keys(nonsensitive(output.http_edge_origin_header_values)), "main"),
      module.http_edge["main"].origin_header_name == "X-Origin-Verify",
      strcontains(
        jsondecode(aws_iam_role_policy.ecs_task_execution_secrets["ui"].policy).Statement[0].Resource,
        "secret:hybridrag-ui-app-*"
      ),
    ])
    error_message = "ECS UI path should create IAM, HTTP edge, name-glob secrets IAM, and typed ecs_apps without ecs_cluster"
  }
}

run "extra_task_policies_attach" {
  command = plan

  variables {
    ecr_repositories = { ui = {} }
    ecs_apps = {
      ui = {
        ecr_key = "ui"
        roles   = [{ database_name = "hybridrag" }]
        extra_task_policies = {
          bedrock-converse = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
        }
      }
    }
  }

  assert {
    condition = alltrue([
      length(aws_iam_role_policy.extra) == 1,
      aws_iam_role_policy.extra["ui-bedrock-converse"].name == "bedrock-converse",
      strcontains(aws_iam_role_policy.extra["ui-bedrock-converse"].policy, "2012-10-17"),
    ])
    error_message = "extra_task_policies should attach one caller-authored task-role policy per entry"
  }
}

run "platform_only_no_public_edge" {
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
