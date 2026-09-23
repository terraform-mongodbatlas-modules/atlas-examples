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
  target          = module.atlas_cluster
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
  atlas_org_id = "org123"
  cluster_name = "hybrid-search-ui"
  llm          = { disabled = true }
}

run "app_secret_nests_groups_without_voyage_key" {
  command = plan

  assert {
    condition = alltrue([
      local.container_secret_keys == ["CHAINLIT_AUTH_SECRET", "CHAINLIT_DEMO_PASSWORD"],
      !contains(local.container_secret_keys, "VOYAGE_API_KEY"),
      local.container_env["ENABLE_LLM"] == "false",
      local.container_env["SKIP_INDEX_CREATION"] == "true",
      !contains(keys(local.container_env), "LLM_PROVIDER"),
      !contains(keys(local.container_env), "BEDROCK_MODEL"),
      module.llm.bedrock.enabled == false,
      strcontains(local.container_env["MONGODB_URI"], "authMechanism=MONGODB-AWS"),
      local.container_env["MONGODB_DATABASE"] == "hybrid_search",
      local.container_env["AUTOEMBED_MODEL"] == "voyage-4-lite",
      local.container_env["TOP_K"] == "20",
      local.container_env["CHUNK_MAX_TOKENS"] == "512",
      local.ui.name == "hybrid-search-ui",
      local.ui.routing.container_port == 8001,
      startswith(output.https_url, "https://"),
      strcontains(output.https_url, "cloudfront.net"),
      output.app_secret_name == "hybrid-search-ui-app",
      contains(local.chainlit_waf_count_rules, "SizeRestrictions_BODY"),
    ])
    error_message = "UI routing, CloudFront https_url, and app secret name should be known at plan"
  }
}

run "waf_count_rules_reach_the_compiled_edge" {
  command = plan

  # app-infra exposes no compiled edge config, so assert the example-side map
  # that feeds module.app_infra.http_edges.
  assert {
    condition = alltrue([
      local.http_edges["main"].waf.disabled == false,
      toset(local.http_edges["main"].waf.common_rule_set_count_rules) == toset(local.chainlit_waf_count_rules),
      length(output.https_url) > 0,
    ])
    error_message = "The Chainlit CRS count rules should reach the compiled app-infra http_edges map with WAF on"
  }
}

run "http_edge_enabled_false_compiles_no_edge" {
  command = plan

  variables {
    http_edge = { enabled = false }
  }

  assert {
    condition = alltrue([
      length(keys(local.http_edges)) == 0,
      try(local.ecs_apps["ui"].routing, null) == null || local.ui.routing == null,
      output.https_url == null,
    ])
    error_message = "http_edge.enabled = false should compile an empty edge map and no routing"
  }
}

run "skip_interface_endpoints_derives_nat" {
  command = plan

  # The derive must satisfy the app-infra vpc.tf precondition that
  # skip_interface_endpoints requires NAT, with no separate internet_egress.
  variables {
    skip_interface_endpoints = true
  }

  assert {
    condition = alltrue([
      module.app_infra.aws.vpcs["us-east-1"].nat_gateway_enabled == true,
      length(keys(local.http_edges)) == 1,
    ])
    error_message = "skip_interface_endpoints = true alone should derive internet_egress and enable NAT"
  }
}
