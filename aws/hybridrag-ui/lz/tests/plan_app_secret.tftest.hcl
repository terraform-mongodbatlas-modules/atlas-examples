mock_provider "mongodbatlas" {
  override_during = plan

  mock_resource "mongodbatlas_ai_model_api_key" {
    defaults = {
      secret     = "al-test-voyage-key"
      endpoint   = "ai.mongodb.com"
      api_key_id = "key-1"
    }
  }
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

  mock_data "aws_secretsmanager_secret_version" {
    defaults = { secret_string = "test-llm-key" }
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
    defaults = { result = "test-origin-or-chainlit-secret" }
  }
}

override_module {
  target          = module.lz.module.atlas_cluster
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

run "app_secret_nests_groups_and_voyage" {
  command = plan

  assert {
    condition = alltrue([
      module.voyage_api_key.api_key_id == "key-1",
      module.voyage_api_key.voyage_base_url == "https://ai.mongodb.com/v1",
      local.container_secret_keys == ["VOYAGE_API_KEY", "CHAINLIT_AUTH_SECRET", "CHAINLIT_DEMO_PASSWORD"],
      local.llm_container_env["ENABLE_LLM"] == "false",
      !contains(keys(local.llm_container_env), "LLM_PROVIDER"),
      local.ui.name == "hybridrag-ui",
      local.ui.routing.container_port == 8001,
      local.ui.routing.origin_header_name == "X-Origin-Verify",
      !contains(keys(local.llm_container_env), "MONGODB_URI"),
      startswith(output.https_url, "https://"),
      strcontains(output.https_url, "cloudfront.net"),
      output.app_secret_name == "hybridrag-ui-app",
    ])
    error_message = "Voyage key, UI routing, CloudFront https_url, and app secret name should be known at plan"
  }
}

run "llm_grove_sets_provider_and_base_url" {
  command = plan

  variables {
    atlas_org_id    = "org123"
    cluster_name    = "hybridrag-ui"
    llm_secret_name = "hybridrag-ui-llm"
    llm_env_name    = "GROVE_API_KEY"
    llm_env = {
      GROVE_BASE_URL = "https://grove.example.mongodb.com/v1"
      GROVE_MODEL    = "gpt-4o"
    }
  }

  assert {
    condition = alltrue([
      sort(local.container_secret_keys) == sort([
        "VOYAGE_API_KEY",
        "CHAINLIT_AUTH_SECRET",
        "CHAINLIT_DEMO_PASSWORD",
        "GROVE_API_KEY",
        "GROVE_BASE_URL",
        "GROVE_MODEL",
      ]),
      local.llm_container_env["ENABLE_LLM"] == "true",
      local.llm_container_env["LLM_PROVIDER"] == "grove",
      !contains(keys(local.llm_container_env), "GROVE_BASE_URL"),
    ])
    error_message = "Grove LLM should set LLM_PROVIDER and inline GROVE_* extras as app secret keys"
  }
}
