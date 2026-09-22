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
    cluster_name = "hybrid-search-ui"
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
  cluster_name    = "hybrid-search-ui"
  enable_llm      = false
  llm_secret_name = null
  llm_env         = {}
}

run "app_secret_nests_groups_without_voyage_key" {
  command = plan

  assert {
    condition = alltrue([
      local.container_secret_keys == ["CHAINLIT_AUTH_SECRET", "CHAINLIT_DEMO_PASSWORD"],
      !contains(local.container_secret_keys, "VOYAGE_API_KEY"),
      local.llm_container_env["ENABLE_LLM"] == "false",
      local.llm_container_env["SKIP_INDEX_CREATION"] == "true",
      !contains(keys(local.llm_container_env), "LLM_PROVIDER"),
      !contains(keys(local.llm_container_env), "BEDROCK_MODEL"),
      local.bedrock_runtime_endpoint == false,
      strcontains(local.llm_container_env["MONGODB_URI"], "authMechanism=MONGODB-AWS"),
      local.llm_container_env["MONGODB_DATABASE"] == "hybrid_search",
      local.llm_container_env["AUTOEMBED_MODEL"] == "voyage-4-lite",
      local.llm_container_env["TOP_K"] == "20",
      local.ui.name == "hybrid-search-ui",
      local.ui.routing.container_port == 8001,
      local.ui.routing.origin_header_name == "X-Origin-Verify",
      startswith(output.https_url, "https://"),
      strcontains(output.https_url, "cloudfront.net"),
      output.app_secret_name == "hybrid-search-ui-app",
      contains(local.chainlit_waf_count_rules, "SizeRestrictions_BODY"),
    ])
    error_message = "UI routing, CloudFront https_url, and app secret name should be known at plan"
  }
}
