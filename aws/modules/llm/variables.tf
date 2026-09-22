variable "enable_llm" {
  description = "Set false for search-only: no LLM answer, no provider inputs consumed, and no bedrock-runtime interface endpoint."
  type        = bool
  default     = true
}

variable "llm_provider" {
  description = "LLM provider when secret_name is null. Null defaults to bedrock, which uses the ECS task role and needs no API key. When secret_name is set and this is set, it must match the provider that env_name infers."
  type        = string
  default     = null
  nullable    = true

  validation {
    condition     = var.llm_provider == null || contains(["anthropic", "bedrock", "openai", "gemini", "grove"], var.llm_provider)
    error_message = "provider must be anthropic, bedrock, openai, gemini, or grove."
  }
}

variable "secret_name" {
  description = "Optional Secrets Manager secret name holding a raw LLM API key. When set, the value is inlined into the app secret JSON and the provider is inferred from env_name. Leave null to use the default bedrock provider, which needs no key."
  type        = string
  default     = null
  nullable    = true

  validation {
    condition = (
      var.secret_name == null ||
      var.llm_provider == null ||
      lookup(local.provider_from_env, var.env_name, null) == var.llm_provider
    )
    error_message = "When secret_name is set and provider is set, provider must match the provider inferred from env_name."
  }

  validation {
    condition = (
      var.secret_name == null ||
      var.env_name != "GROVE_API_KEY" ||
      try(var.env["GROVE_BASE_URL"], "") != ""
    )
    error_message = "Grove requires env.GROVE_BASE_URL."
  }
}

variable "secret_value" {
  description = "Resolved secret value for secret_name. The caller reads data.aws_secretsmanager_secret_version and passes secret_string; null inlines nothing."
  type        = string
  default     = null
  nullable    = true
  sensitive   = true
}

variable "env_name" {
  description = "Container env name for the optional LLM key. Infers the provider when secret_name is set: ANTHROPIC_API_KEY=anthropic, OPENAI_API_KEY=openai, GEMINI_API_KEY=gemini, GROVE_API_KEY=grove. Ignored when secret_name is null."
  type        = string
  default     = "ANTHROPIC_API_KEY"
}

variable "env" {
  description = "Extra LLM values inlined into the app secret JSON (ANTHROPIC_MODEL, BEDROCK_MODEL, GEMINI_MODEL, OPENAI_MODEL, OPENAI_BASE_URL, OPENAI_EXTRA_HEADERS, GROVE_BASE_URL, GROVE_MODEL). Do not put the API key here; use secret_name. aws_region is set for the bedrock provider; set env.BEDROCK_MODEL to override the default model."
  type        = map(string)
  default     = {}

  validation {
    condition     = !contains(keys(var.env), var.env_name)
    error_message = "env must not include env_name; that key comes from secret_name."
  }
}

variable "aws_region" {
  description = "AWS region for the bedrock provider; written to AWS_REGION in the container env."
  type        = string
}

variable "bedrock_model_default" {
  description = "Bedrock model id used when env.BEDROCK_MODEL is not set."
  type        = string
  default     = "amazon.nova-lite-v1:0"
}
