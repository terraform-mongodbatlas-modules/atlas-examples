locals {
  provider_from_env = {
    ANTHROPIC_API_KEY = "anthropic"
    OPENAI_API_KEY    = "openai"
    GEMINI_API_KEY    = "gemini"
    GROVE_API_KEY     = "grove"
  }

  # Secret-first: a secret name still selects the keyed provider from env_name,
  # so existing configs are unaffected. Otherwise the explicit provider wins.
  provider_from_secret = var.secret_name != null ? lookup(local.provider_from_env, var.env_name, null) : null
  provider             = coalesce(local.provider_from_secret, var.llm_provider, "bedrock")

  bedrock_enabled = var.enable_llm && local.provider == "bedrock"
  bedrock_model   = coalesce(try(var.env["BEDROCK_MODEL"], null), var.bedrock_model_default)

  env = merge(
    { ENABLE_LLM = var.enable_llm ? "true" : "false" },
    var.enable_llm ? { LLM_PROVIDER = local.provider } : {},
    local.bedrock_enabled ? {
      BEDROCK_MODEL = local.bedrock_model
      AWS_REGION    = var.aws_region
    } : {}
  )

  # The keyed provider value is inlined into the app secret under env_name, plus
  # any extra provider values (for example GROVE_BASE_URL).
  secrets = var.enable_llm && var.secret_name != null ? merge(
    { (var.env_name) = var.secret_value },
    var.env
  ) : {}

  # The ECS task role calls Bedrock Converse directly; no API key and no secret.
  # Cross-region inference profiles route the second hop in another region, so
  # the policy covers every region's foundation-model ARNs via the wildcard.
  # GetInferenceProfile is required when the model names an inference profile
  # (the `us.` ids); without it those calls are an implicit deny.
  task_policy_jsons = local.bedrock_enabled ? {
    bedrock-converse = jsonencode({
      Version = "2012-10-17"
      Statement = [
        {
          Effect = "Allow"
          Action = [
            "bedrock:InvokeModel",
            "bedrock:InvokeModelWithResponseStream",
            "bedrock:Converse",
            "bedrock:ConverseStream",
          ]
          Resource = [
            "arn:aws:bedrock:*::foundation-model/*",
            "arn:aws:bedrock:*:*:inference-profile/*",
          ]
        },
        {
          Effect   = "Allow"
          Action   = ["bedrock:GetInferenceProfile"]
          Resource = ["arn:aws:bedrock:*:*:inference-profile/*"]
        },
      ]
    })
  } : {}
}
