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

run "interface_endpoints_default" {
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
        }
        roles = [{ database_name = "hybridrag" }]
      }
    }
  }

  assert {
    condition = alltrue([
      length(aws_vpc_endpoint.interface) == 5,
      length(aws_vpc_endpoint.s3) == 1,
      length(aws_security_group.vpc_endpoints) == 1,
    ])
    error_message = "ECS app region should get five interface endpoints, one S3 gateway, and one vpc_endpoints SG"
  }
}

run "skip_interface_endpoints" {
  command = plan

  variables {
    ecr_repositories = { ui = {} }
    http_edges       = { main = {} }
    vpc_config       = { skip_interface_endpoints = true }
    ecs_apps = {
      ui = {
        name            = "hybridrag-ui"
        ecr_key         = "ui"
        internet_egress = true
        routing = {
          edge              = "main"
          path_pattern      = ["/*"]
          listener_priority = 100
        }
        roles = [{ database_name = "hybridrag" }]
      }
    }
  }

  assert {
    condition = alltrue([
      length(aws_vpc_endpoint.interface) == 0,
      length(aws_vpc_endpoint.s3) == 1,
      length(aws_security_group.vpc_endpoints) == 0,
    ])
    error_message = "skip_interface_endpoints should omit interface endpoints and vpc_endpoints SG but keep S3"
  }
}

run "skip_interface_endpoints_requires_nat" {
  command = plan

  variables {
    ecr_repositories = { ui = {} }
    http_edges       = { main = {} }
    vpc_config       = { skip_interface_endpoints = true }
    ecs_apps = {
      ui = {
        name    = "hybridrag-ui"
        ecr_key = "ui"
        routing = {
          edge              = "main"
          path_pattern      = ["/*"]
          listener_priority = 100
        }
        roles = [{ database_name = "hybridrag" }]
      }
    }
  }

  expect_failures = [
    aws_vpc_endpoint.s3,
  ]
}
