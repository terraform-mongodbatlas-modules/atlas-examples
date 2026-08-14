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
  atlas_org_id    = "org123"
  cluster_name    = "hybridrag-ui"
  llm_secret_name = null
  llm_env         = {}
}

run "app_secret_nests_groups_and_voyage" {
  command = plan

  assert {
    condition = alltrue([
      module.voyage_api_key.api_key_id == "key-1",
      module.voyage_api_key.voyage_base_url == "https://ai.mongodb.com/v1",
      local.container_secret_keys == ["VOYAGE_API_KEY", "CHAINLIT_AUTH_SECRET", "CHAINLIT_DEMO_PASSWORD"],
      local.llm_container_env["ENABLE_LLM"] == "false",
      local.llm_container_env["SKIP_INDEX_CREATION"] == "true",
      !contains(keys(local.llm_container_env), "LLM_PROVIDER"),
      strcontains(local.llm_container_env["MONGODB_URI"], "authMechanism=MONGODB-AWS"),
      local.llm_container_env["MONGODB_DATABASE"] == "hybridrag",
      local.llm_container_env["VOYAGE_BASE_URL"] == "https://ai.mongodb.com/v1",
      local.llm_container_env["DEFAULT_QUERY_MODE"] == "mix",
      local.llm_container_env["DEFAULT_TOP_K"] == "60",
      local.llm_container_env["DEFAULT_RERANK_TOP_K"] == "10",
      local.llm_container_env["ENABLE_RERANK"] == "true",
      local.llm_container_env["ENABLE_ENTITY_BOOSTING"] == "true",
      local.llm_container_env["ENABLE_IMPLICIT_EXPANSION"] == "true",
      !contains(local.container_secret_keys, "VOYAGE_BASE_URL"),
      local.ui.name == "hybridrag-ui",
      local.ui.routing.container_port == 8001,
      local.ui.routing.origin_header_name == "X-Origin-Verify",
      startswith(output.https_url, "https://"),
      strcontains(output.https_url, "cloudfront.net"),
      output.app_secret_name == "hybridrag-ui-app",
      contains(local.chainlit_waf_count_rules, "SizeRestrictions_BODY"),
    ])
    error_message = "Voyage key, UI routing, CloudFront https_url, and app secret name should be known at plan"
  }
}
