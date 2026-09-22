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
  llm_secret_name = "hybrid-search-ui-llm"
  llm_env_name    = "GROVE_API_KEY"
  llm_env = {
    GROVE_BASE_URL = "https://grove.example.mongodb.com/v1"
    GROVE_MODEL    = "gpt-4o"
  }
}

run "llm_grove_sets_provider_and_base_url" {
  command = plan

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
      local.llm_container_env["SKIP_INDEX_CREATION"] == "true",
      local.llm_container_env["LLM_PROVIDER"] == "grove",
      local.llm_container_env["MONGODB_URI"] != "",
      local.llm_container_env["MONGODB_DATABASE"] == "hybrid_search",
      local.llm_container_env["VOYAGE_BASE_URL"] == "https://ai.mongodb.com/v1",
      local.llm_container_env["TOP_K"] == "20",
      !contains(keys(local.llm_container_env), "GROVE_BASE_URL"),
      local.bedrock_runtime_endpoint == false,
    ])
    error_message = "Grove LLM should set LLM_PROVIDER and inline GROVE_* extras as app secret keys, without a bedrock endpoint"
  }
}

run "bedrock_is_default_with_no_key" {
  command = plan

  variables {
    llm_secret_name = null
    llm_env_name    = "ANTHROPIC_API_KEY"
    llm_env         = {}
  }

  assert {
    condition = alltrue([
      sort(local.container_secret_keys) == sort([
        "VOYAGE_API_KEY",
        "CHAINLIT_AUTH_SECRET",
        "CHAINLIT_DEMO_PASSWORD",
      ]),
      local.llm_container_env["ENABLE_LLM"] == "true",
      local.llm_container_env["LLM_PROVIDER"] == "bedrock",
      local.llm_container_env["BEDROCK_MODEL"] == "amazon.nova-lite-v1:0",
      local.llm_container_env["AWS_REGION"] == "us-east-1",
      local.bedrock_enabled == true,
      local.bedrock_runtime_endpoint == true,
    ])
    error_message = "Default should select bedrock, set BEDROCK_MODEL and AWS_REGION, and infer the bedrock-runtime endpoint"
  }
}

run "enable_llm_false_is_search_only" {
  command = plan

  variables {
    enable_llm      = false
    llm_secret_name = null
    llm_env         = {}
  }

  assert {
    condition = alltrue([
      local.llm_container_env["ENABLE_LLM"] == "false",
      !contains(keys(local.llm_container_env), "LLM_PROVIDER"),
      !contains(keys(local.llm_container_env), "BEDROCK_MODEL"),
      length(local.container_secret_keys) == 3,
      local.bedrock_enabled == false,
      local.bedrock_runtime_endpoint == false,
    ])
    error_message = "enable_llm = false should disable the LLM and omit the bedrock endpoint"
  }
}

run "bedrock_runtime_endpoint_can_be_disabled_explicitly" {
  command = plan

  variables {
    llm_secret_name = null
    llm_env         = {}
    vpc_config      = { bedrock_runtime_endpoint = false }
  }

  assert {
    condition = alltrue([
      local.llm_container_env["LLM_PROVIDER"] == "bedrock",
      local.bedrock_enabled == true,
      local.bedrock_runtime_endpoint == false,
    ])
    error_message = "An explicit bedrock_runtime_endpoint = false should override the bedrock inference"
  }
}

run "llm_provider_must_match_secret_key_name" {
  command = plan

  variables {
    llm_secret_name = "hybrid-search-ui-llm"
    llm_env_name    = "GROVE_API_KEY"
    llm_provider    = "anthropic"
    llm_env = {
      GROVE_BASE_URL = "https://grove.example.mongodb.com/v1"
    }
  }

  expect_failures = [
    var.llm_secret_name,
  ]
}
