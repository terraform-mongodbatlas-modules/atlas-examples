# `modules/llm`

LLM provider selection as a pure transform. The module creates no resources, so
it can be called before the app infra without a dependency cycle.

Given the provider knobs from tfvars, it resolves the provider, builds the
container env map, and returns the IAM task-role policy the app infra should
attach for Bedrock. The caller keeps ownership of the app secret and the
`aws_secretsmanager_secret_version` data source.

## Provider inference

- **`secret_name` set:** The provider comes from `env_name` (`ANTHROPIC_API_KEY` to `anthropic`, `OPENAI_API_KEY` to `openai`, `GEMINI_API_KEY` to `gemini`, `GROVE_API_KEY` to `grove`). If `llm_provider` is also set it must match, or the module fails.
- **`secret_name` null and `llm_provider` set:** The explicit provider wins.
- **Both null:** The provider defaults to `bedrock`, which needs no key.

`bedrock` also sets `BEDROCK_MODEL` (from `env.BEDROCK_MODEL`, else `bedrock_model_default`) and `AWS_REGION` in the container env, and returns a `bedrock-converse` task-role policy that allows the Converse actions plus `GetInferenceProfile` for inference-profile model ids (the `us.` ids).

## Inputs

- **`enable_llm`:** `false` for search-only. Omits `LLM_PROVIDER`, `BEDROCK_MODEL`, and the bedrock policy.
- **`llm_provider` / `secret_name` / `env_name`:** See provider inference. `secret_name` requires `env_name` and, for Grove, `env.GROVE_BASE_URL`.
- **`secret_value`:** The resolved secret string from the caller's `data.aws_secretsmanager_secret_version`. Inlined under `env_name` when `secret_name` is set.
- **`env`:** Extra provider values inlined as app secret keys (`ANTHROPIC_MODEL`, `GEMINI_MODEL`, `OPENAI_MODEL`, `OPENAI_BASE_URL`, `OPENAI_EXTRA_HEADERS`, `GROVE_MODEL`, `BEDROCK_MODEL`). Do not put the API key here.
- **`aws_region` / `bedrock_model_default`:** Region written to `AWS_REGION` and the Bedrock model fallback.

## Outputs

- **`env`:** Container env map with the LLM keys (`ENABLE_LLM`, `LLM_PROVIDER`, and for bedrock `BEDROCK_MODEL` / `AWS_REGION`). The caller merges this with its own app env (`MONGODB_URI`, `MONGODB_DATABASE`, `TOP_K`, `CHUNK_MAX_TOKENS`, `AUTOEMBED_MODEL`).
- **`secret_keys`:** Secret key names the container reads. Always `CHAINLIT_AUTH_SECRET` and `CHAINLIT_DEMO_PASSWORD`; adds `env_name` plus `env` keys when a secret is set.
- **`secrets`:** Sensitive map to merge into the app secret JSON. Empty when no secret is set.
- **`bedrock`:** `{ enabled, model, region }`. `enabled` drives the `bedrock-runtime` interface endpoint on the app infra.
- **`task_policy_jsons`:** Map of policy name to JSON for the app infra's `extra_task_policies`. Empty when the provider is not Bedrock.
