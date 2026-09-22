output "env" {
  description = "Container env for the LLM provider. Includes LLM_PROVIDER and, for bedrock, BEDROCK_MODEL and AWS_REGION. The caller merges this with its own app env."
  value       = local.env
}

output "secret_keys" {
  description = "App secret keys the container reads. Always CHAINLIT_AUTH_SECRET and CHAINLIT_DEMO_PASSWORD; adds env_name plus env keys when secret_name is set."
  value = concat(
    ["CHAINLIT_AUTH_SECRET", "CHAINLIT_DEMO_PASSWORD"],
    sort(keys(local.secrets))
  )
}

output "secrets" {
  description = "Sensitive secret values to merge into the app secret JSON when secret_name is set. Empty otherwise."
  value       = local.secrets
  sensitive   = true
}

output "bedrock" {
  description = "Bedrock provider state. enabled drives the bedrock-runtime interface endpoint on the app infra; model and region are the resolved values."
  value = {
    enabled = local.bedrock_enabled
    model   = local.bedrock_model
    region  = var.aws_region
  }
}

output "task_policy_jsons" {
  description = "IAM task-role policies the app infra should attach, keyed by policy name. Empty when the provider is not bedrock. Pass this to extra_task_policies on the app infra."
  value       = local.task_policy_jsons
}
