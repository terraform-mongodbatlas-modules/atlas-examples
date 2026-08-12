mock_provider "mongodbatlas" {
  override_during = plan
}
mock_provider "aws" {
  override_during = plan
  mock_data "aws_availability_zones" {
    defaults = { names = ["us-east-1a", "us-east-1b", "us-east-1c", "us-east-1d", "us-east-1e", "us-east-1f"] }
  }
  mock_data "aws_secretsmanager_secret" {
    defaults = {
      arn = "arn:aws:secretsmanager:us-east-1:123456789012:secret:byo-secret"
    }
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

override_module {
  target          = module.atlas_ai_model_api_key["hybridrag"]
  override_during = plan
  outputs = {
    secret_arn      = "arn:aws:secretsmanager:us-east-1:123456789012:secret:hybridrag-voyage"
    voyage_base_url = "https://voyage.example.mongodb.com/v1"
    api_key_id      = "al-key-id"
  }
}

variables {
  atlas_org_id = "org123"
  cluster_name = "fastapi-minimal"
}

run "hybridrag_handoff_payload" {
  command = plan

  variables {
    lambda_apps      = {}
    ecr_repositories = { hybridrag = {} }
    http_edges       = { main = {} }
    ecs_apps = {
      hybridrag = {
        ecr_key                = "hybridrag"
        routing                = { edge = "main", path_pattern = ["/*"], listener_priority = 100 }
        roles                  = [{ database_name = "hybridrag" }]
        handoff_secret         = {}
        atlas_ai_model_api_key = { key_name = "fastapi-minimal-voyage" }
        internet_egress        = true
        container_env_vars = {
          ENABLE_LLM = "false"
        }
      }
    }
  }

  assert {
    condition = alltrue([
      local.ecs_apps["hybridrag"].routing.health_check_path == "/health",
      local.ecs_apps["hybridrag"].container_env_vars["ENABLE_LLM"] == "false",
      local.ecs_apps["hybridrag"].atlas_ai_model_api_key.key_name == "fastapi-minimal-voyage",
      local.ecs_apps["hybridrag"].internet_egress,
      local.enable_nat_gateway_by_region["us-east-1"],
      length([
        for e in aws_security_group.lambda["us-east-1"].egress : e
        if e.description == "Internet HTTPS via NAT (ecs_apps internet_egress or vpc_config.enable_nat_gateway)"
      ]) == 1,
      length(module.vpc["us-east-1"].natgw_ids) == 1,
      length(aws_iam_role_policy.ecs_task_execution_secrets) == 1,
      length(aws_secretsmanager_secret.ecs_app) == 1,
      length(module.atlas_ai_model_api_key) == 1,
    ])
    error_message = "HybridRAG ecs_apps should wire Voyage module, SM handoff, NAT, internet egress, and /health default"
  }
}

run "hybridrag_api_key_secret" {
  command = plan

  variables {
    lambda_apps      = {}
    ecr_repositories = { hybridrag = {} }
    http_edges       = { main = {} }
    ecs_apps = {
      hybridrag = {
        ecr_key                = "hybridrag"
        routing                = { edge = "main", path_pattern = ["/*"], listener_priority = 100 }
        roles                  = [{ database_name = "hybridrag" }]
        handoff_secret         = {}
        api_key_secret         = {}
        atlas_ai_model_api_key = { key_name = "fastapi-minimal-voyage" }
        internet_egress        = true
      }
    }
  }

  assert {
    condition = alltrue([
      length(module.ecs_api_key_secret) == 1,
      contains(keys(local.ecs_app_handoff_payloads["hybridrag"].container_secret_env_vars), "HYBRIDRAG_API_KEY"),
      length(aws_iam_role_policy.ecs_task_execution_secrets) == 1,
    ])
    error_message = "api_key_secret should create SM secret, handoff HYBRIDRAG_API_KEY, and execution role policy"
  }
}

run "api_key_secret_byo_exclusive" {
  command = plan

  variables {
    lambda_apps      = {}
    ecr_repositories = { api = {} }
    http_edges       = { main = {} }
    ecs_apps = {
      api = {
        ecr_key        = "api"
        routing        = { edge = "main", path_pattern = ["/*"], listener_priority = 100 }
        roles          = [{ database_name = "test" }]
        handoff_secret = {}
        api_key_secret = {}
        container_secrets = {
          HYBRIDRAG_API_KEY = { name = "byo-secret" }
        }
      }
    }
  }

  expect_failures = [
    var.ecs_apps,
  ]
}

run "ecs_tfvars_and_secret_exclusive" {
  command = plan

  variables {
    lambda_apps      = {}
    ecr_repositories = { api = {} }
    http_edges       = { main = {} }
    ecs_apps = {
      api = {
        ecr_key        = "api"
        routing        = { edge = "main", path_pattern = ["/*"], listener_priority = 100 }
        roles          = [{ database_name = "test" }]
        tfvars_path    = "../02_app_ecs/infra.auto.tfvars"
        handoff_secret = {}
      }
    }
  }

  expect_failures = [
    var.ecs_apps,
  ]
}

run "container_secrets_byo" {
  command = plan

  variables {
    lambda_apps      = {}
    ecr_repositories = { api = {} }
    http_edges       = { main = {} }
    ecs_apps = {
      api = {
        ecr_key        = "api"
        routing        = { edge = "main", path_pattern = ["/*"], listener_priority = 100 }
        roles          = [{ database_name = "test" }]
        handoff_secret = {}
        container_secrets = {
          API_TOKEN = { name = "byo-secret" }
        }
      }
    }
  }

  assert {
    condition = alltrue([
      length(data.aws_secretsmanager_secret.ecs_container) == 1,
      contains(keys(local.ecs_apps["api"].container_secrets), "API_TOKEN"),
      length(aws_iam_role_policy.ecs_task_execution_secrets) == 1,
    ])
    error_message = "BYO container_secrets should resolve SM lookup and execution role policy"
  }
}
