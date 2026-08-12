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

run "chainlit_secret_byo_exclusive" {
  command = plan

  variables {
    lambda_apps      = {}
    ecr_repositories = { ui = {} }
    http_edges       = { main = {} }
    ecs_apps = {
      ui = {
        ecr_key              = "ui"
        routing              = { edge = "main", path_pattern = ["/*"], listener_priority = 100, container_port = 8001 }
        roles                = [{ database_name = "test" }]
        handoff_secret       = {}
        chainlit_auth_secret = {}
        container_secrets = {
          CHAINLIT_AUTH_SECRET = { name = "byo-secret" }
        }
      }
    }
  }

  expect_failures = [
    var.ecs_apps,
  ]
}

run "ui_demo_password_byo_exclusive" {
  command = plan

  variables {
    lambda_apps      = {}
    ecr_repositories = { ui = {} }
    http_edges       = { main = {} }
    ecs_apps = {
      ui = {
        ecr_key             = "ui"
        routing             = { edge = "main", path_pattern = ["/*"], listener_priority = 100, container_port = 8001 }
        roles               = [{ database_name = "test" }]
        handoff_secret      = {}
        ui_demo_credentials = {}
        container_secrets = {
          CHAINLIT_DEMO_PASSWORD = { name = "byo-secret" }
        }
      }
    }
  }

  expect_failures = [
    var.ecs_apps,
  ]
}

run "hybridrag_ui_handoff" {
  command = plan

  variables {
    lambda_apps = {}
    ecr_repositories = {
      hybridrag_ui = {}
    }
    http_edges = { main = {} }
    ecs_apps = {
      hybridrag_ui = {
        ecr_key = "hybridrag_ui"
        routing = {
          edge              = "main"
          listener_priority = 200
          path_pattern      = ["/*"]
          container_port    = 8001
          health_check_path = "/"
        }
        roles                = [{ database_name = "hybridrag" }]
        handoff_secret       = { name = "hybridrag-ui-app" }
        chainlit_auth_secret = {}
        ui_demo_credentials  = {}
        task_cpu             = "1024"
        task_memory          = "2048"
        container_env_vars = {
          CHAINLIT_DEMO_USERNAME = "demo"
        }
      }
    }
  }

  assert {
    condition = alltrue([
      length(module.ecs_chainlit_auth_secret) == 1,
      length(module.ecs_ui_demo_password) == 1,
      local.ecs_app_handoff_payloads["hybridrag_ui"].container_port == 8001,
      local.ecs_app_handoff_payloads["hybridrag_ui"].task_memory == "2048",
      contains(keys(local.ecs_app_handoff_payloads["hybridrag_ui"].container_secret_env_vars), "CHAINLIT_AUTH_SECRET"),
      contains(keys(local.ecs_app_handoff_payloads["hybridrag_ui"].container_secret_env_vars), "CHAINLIT_DEMO_PASSWORD"),
    ])
    error_message = "hybridrag_ui handoff should wire Chainlit auth secrets and task size"
  }
}
