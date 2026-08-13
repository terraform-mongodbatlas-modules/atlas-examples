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

run "ecs_without_http_edge" {
  command = plan

  variables {
    ecr_repositories = { ui = {} }
    ecs_apps = {
      ui = {
        ecr_key = "ui"
        roles   = [{ database_name = "hybridrag" }]
      }
    }
  }

  assert {
    condition = alltrue([
      length(aws_iam_role.ecs_task) == 1,
      length(module.http_edge) == 0,
      length(module.vpc["us-east-1"].public_subnets) == 0,
    ])
    error_message = "ecs_apps without http_edges should not create ALB or public subnets"
  }
}

run "duplicate_listener_priority" {
  command = plan

  variables {
    ecr_repositories = { api = {}, ui = {} }
    http_edges       = { main = {} }
    ecs_apps = {
      api = {
        ecr_key = "api"
        routing = { edge = "main", path_pattern = ["/api"], listener_priority = 100 }
        roles   = [{ database_name = "test" }]
      }
      ui = {
        ecr_key = "ui"
        routing = { edge = "main", path_pattern = ["/*"], listener_priority = 100 }
        roles   = [{ database_name = "test" }]
      }
    }
  }

  expect_failures = [
    var.ecs_apps,
  ]
}

run "missing_edge_reference" {
  command = plan

  variables {
    ecr_repositories = { ui = {} }
    http_edges       = { main = {} }
    ecs_apps = {
      ui = {
        ecr_key = "ui"
        routing = { edge = "other", path_pattern = ["/*"], listener_priority = 100 }
        roles   = [{ database_name = "hybridrag" }]
      }
    }
  }

  expect_failures = [
    var.ecs_apps,
  ]
}

run "routing_missing_match" {
  command = plan

  variables {
    ecr_repositories = { ui = {} }
    http_edges       = { main = {} }
    ecs_apps = {
      ui = {
        ecr_key = "ui"
        routing = { edge = "main", listener_priority = 100 }
        roles   = [{ database_name = "hybridrag" }]
      }
    }
  }

  expect_failures = [
    var.ecs_apps,
  ]
}

run "aliases_without_cert" {
  command = plan

  variables {
    http_edges = {
      main = { aliases = ["api.example.com"] }
    }
  }

  expect_failures = [
    var.http_edges,
  ]
}

run "cert_wrong_region" {
  command = plan

  variables {
    http_edges = {
      main = {
        aliases             = ["api.example.com"]
        acm_certificate_arn = "arn:aws:acm:us-east-2:123456789012:certificate/abc"
      }
    }
  }

  expect_failures = [
    var.http_edges,
  ]
}

run "custom_domain_valid" {
  command = plan

  variables {
    ecr_repositories = { ui = {} }
    http_edges = {
      main = {
        aliases             = ["ui.example.com"]
        acm_certificate_arn = "arn:aws:acm:us-east-1:123456789012:certificate/abc"
      }
    }
    ecs_apps = {
      ui = {
        ecr_key = "ui"
        routing = { edge = "main", path_pattern = ["/*"], listener_priority = 100 }
        roles   = [{ database_name = "hybridrag" }]
      }
    }
  }

  assert {
    condition     = module.http_edge["main"].https_url == "https://ui.example.com"
    error_message = "https_url should use the first alias when set"
  }
}
