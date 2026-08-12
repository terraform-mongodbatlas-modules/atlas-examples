# HybridRAG backend (ECS)

Minimal deploy path for the upstream [Hybrid-Search-RAG](https://github.com/romiluz13/Hybrid-Search-RAG) API on ECS. See the main [README](../README.md) for Landing Zone setup.

## Prerequisites

- `01_lz` applied with `ecs_apps.hybridrag`, `handoff_secret = {}`, `api_key_secret = {}`, `atlas_ai_model_api_key`, and `internet_egress = true` (see `01_lz/terraform.tfvars.example`). `internet_egress` creates a NAT gateway and allows HTTPS egress so HybridRAG can download tiktoken encodings and call the Voyage API. By default `vpc_config.single_nat_gateway` is `true` (one shared NAT across AZs).
- AWS CLI, Docker, `just`, and `jq`.
- **Provider:** `atlas_ai_model_api_key` needs mongodbatlas provider **2.16+** (unreleased on the registry at time of writing). For local apply, build provider `master` and copy [`.terraformrc.example`](../.terraformrc.example) to `~/.terraformrc` (adjust the binary path).

## Deploy

The ECS image is built from upstream HybridRAG sources plus `docker/Dockerfile.hybridrag`, which adds `pymongo[aws]` so `authMechanism=MONGODB-AWS` works with the ECS task role.

```sh
# 1. Landing zone + Voyage key + API key + handoff secret (hybridrag-app)
terraform -chdir=01_lz apply

# 2. Build and push image
just clone-hybridrag
just build-push-backend "$(terraform -chdir=01_lz output -json ecr_repositories | jq -r '.hybridrag')"

# 3. ECS service (reads handoff from SM; set handoff_secret_name in 02_app_ecs/terraform.tfvars)
terraform -chdir=02_app_ecs apply
```

`02_app_ecs` needs only `handoff_secret_name = "hybridrag-app"` and `image_tag` when using the SM handoff path. Legacy file handoff via `tfvars_path` is still supported; see the main README.

## API key auth

When `api_key_secret = {}` is set on the HybridRAG `ecs_apps` entry, `01_lz` generates a key in Secrets Manager and injects `HYBRIDRAG_API_KEY` into the ECS task. `/v1/*` routes require header `X-API-Key` with a matching value. `/health` and `/ready` stay open for the ALB health check. `/docs` and `/openapi.json` remain public (upstream FastAPI defaults).

CloudFront uses the managed `AllViewerExceptHostHeader` origin request policy so viewer headers (including `X-API-Key` and `Content-Type`) reach the ALB. Without an origin request policy, CloudFront would not forward those headers to the origin.

BYO key: omit `api_key_secret` and set `container_secrets = { HYBRIDRAG_API_KEY = { name = "my-precreated-api-key" } }` instead. Do not set both.

Retrieve the managed key:

```sh
aws secretsmanager get-secret-value --secret-id hybridrag-api-key --query SecretString --output text
```

## Smoke test

```sh
BASE="$(terraform -chdir=01_lz output -json aws | jq -r '.http_edges.main.https_url')"
KEY="$(aws secretsmanager get-secret-value --secret-id hybridrag-api-key --query SecretString --output text)"

curl -fsS "${BASE}/health" | jq .

curl -fsS -X POST "${BASE}/v1/query" \
  -H "Content-Type: application/json" \
  -H "X-API-Key: ${KEY}" \
  -d '{"query":"test","mode":"naive"}' | jq .
```

Expect `"status": "healthy"` on `/health` after Mongo connects and indexes warm up (first boot can take a few minutes). A `/v1/query` without `X-API-Key` returns `403` when the key is enabled.
