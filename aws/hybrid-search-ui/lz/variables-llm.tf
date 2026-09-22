# LLM answer for the UI. module.llm resolves the provider, container env, secret
# keys, and the Bedrock task-role policy; the provider validations live in
# ../../modules/llm next to the logic they guard.
#
# Default: Amazon Bedrock with no key and no secret (the ECS task role calls the
# provider over a private bedrock-runtime interface endpoint). Keyed providers
# (anthropic, openai, gemini, grove) set secret_name; the provider is inferred
# from env_name unless provider is set explicitly. grove also needs
# env.GROVE_BASE_URL.

# --- LLM ----------------------------------------------------------------------

variable "llm" {
  description = <<-EOT
    LLM answer for the UI. On by default with Amazon Bedrock: the ECS task role calls
    the provider, so there is no key and no secret. Set secret_name to use a keyed
    provider instead; the provider is inferred from env_name unless you set provider
    explicitly.
  EOT
  type = object({
    disabled    = optional(bool, false)
    provider    = optional(string)
    secret_name = optional(string)
    env_name    = optional(string, "ANTHROPIC_API_KEY")
    env         = optional(map(string), {})
  })
  default = {}
}
