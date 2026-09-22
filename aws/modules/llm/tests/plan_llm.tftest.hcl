variables {
  aws_region = "us-east-1"
}

run "grove_keyed_sets_provider_and_secret_keys" {
  command = plan

  variables {
    secret_name  = "hybrid-search-ui-llm"
    secret_value = "test-llm-key"
    env_name     = "GROVE_API_KEY"
    env = {
      GROVE_BASE_URL = "https://grove.example.mongodb.com/v1"
      GROVE_MODEL    = "gpt-4o"
    }
  }

  assert {
    condition = alltrue([
      local.provider == "grove",
      local.bedrock_enabled == false,
      output.env["ENABLE_LLM"] == "true",
      output.env["LLM_PROVIDER"] == "grove",
      !contains(keys(output.env), "BEDROCK_MODEL"),
      output.bedrock.enabled == false,
      length(output.task_policy_jsons) == 0,
      sort(output.secret_keys) == sort([
        "CHAINLIT_AUTH_SECRET",
        "CHAINLIT_DEMO_PASSWORD",
        "GROVE_API_KEY",
        "GROVE_BASE_URL",
        "GROVE_MODEL",
      ]),
      nonsensitive(output.secrets["GROVE_API_KEY"]) == "test-llm-key",
    ])
    error_message = "Grove should infer LLM_PROVIDER, inline the key and GROVE_* extras as secret keys, and skip the bedrock endpoint"
  }
}

run "bedrock_is_default_with_no_key" {
  command = plan

  assert {
    condition = alltrue([
      local.provider == "bedrock",
      local.bedrock_enabled == true,
      output.env["ENABLE_LLM"] == "true",
      output.env["LLM_PROVIDER"] == "bedrock",
      output.env["BEDROCK_MODEL"] == "amazon.nova-lite-v1:0",
      output.env["AWS_REGION"] == "us-east-1",
      output.bedrock.enabled == true,
      output.bedrock.model == "amazon.nova-lite-v1:0",
      length(output.secret_keys) == 2,
      length(output.task_policy_jsons) == 1,
      strcontains(output.task_policy_jsons["bedrock-converse"], "bedrock:Converse"),
      strcontains(output.task_policy_jsons["bedrock-converse"], "arn:aws:bedrock:*:*:inference-profile/*"),
      strcontains(output.task_policy_jsons["bedrock-converse"], "bedrock:GetInferenceProfile"),
    ])
    error_message = "Default should select bedrock, set BEDROCK_MODEL and AWS_REGION, and grant the Converse plus GetInferenceProfile policy"
  }
}

run "bedrock_model_can_be_overridden" {
  command = plan

  variables {
    env = { BEDROCK_MODEL = "us.amazon.nova-2-lite-v1:0" }
  }

  assert {
    condition     = output.env["BEDROCK_MODEL"] == "us.amazon.nova-2-lite-v1:0"
    error_message = "env.BEDROCK_MODEL should override bedrock_model_default"
  }
}

run "enable_llm_false_is_search_only" {
  command = plan

  variables {
    enable_llm = false
  }

  assert {
    condition = alltrue([
      output.env["ENABLE_LLM"] == "false",
      !contains(keys(output.env), "LLM_PROVIDER"),
      !contains(keys(output.env), "BEDROCK_MODEL"),
      length(output.secret_keys) == 2,
      output.bedrock.enabled == false,
      length(output.task_policy_jsons) == 0,
    ])
    error_message = "enable_llm = false should disable the LLM and omit the bedrock policy"
  }
}

run "llm_provider_must_match_secret_key_name" {
  command = plan

  variables {
    secret_name  = "hybrid-search-ui-llm"
    secret_value = "test-llm-key"
    env_name     = "GROVE_API_KEY"
    llm_provider = "anthropic"
    env = {
      GROVE_BASE_URL = "https://grove.example.mongodb.com/v1"
    }
  }

  expect_failures = [
    var.secret_name,
  ]
}

run "grove_requires_base_url" {
  command = plan

  variables {
    secret_name  = "hybrid-search-ui-llm"
    secret_value = "test-llm-key"
    env_name     = "GROVE_API_KEY"
  }

  expect_failures = [
    var.secret_name,
  ]
}
