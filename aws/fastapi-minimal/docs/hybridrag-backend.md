# HybridRAG backend (ECS)

Minimal deploy path for the upstream [Hybrid-Search-RAG](https://github.com/romiluz13/Hybrid-Search-RAG) API on ECS. See the main [README](../README.md) for Landing Zone setup.

## Prerequisites

- `01_lz` applied with `ecs_apps.hybridrag`, `handoff_secret = {}`, `atlas_ai_model_api_key`, and `internet_egress = true` (see `01_lz/terraform.tfvars.example`). `internet_egress` creates a NAT gateway and allows HTTPS egress so HybridRAG can download tiktoken encodings and call the Voyage API. By default `vpc_config.single_nat_gateway` is `true` (one shared NAT across AZs).
- AWS CLI, Docker, `just`, and `jq`.
- **Provider:** `atlas_ai_model_api_key` needs mongodbatlas provider **2.16+** (unreleased on the registry at time of writing). For local apply, build provider `master` and copy [`.terraformrc.example`](../.terraformrc.example) to `~/.terraformrc` (adjust the binary path).

## Deploy

```sh
# 1. Landing zone + Voyage key + handoff secret (hybridrag-app)
terraform -chdir=01_lz apply

# 2. Build and push image
just clone-hybridrag
just build-push-backend "$(terraform -chdir=01_lz output -json ecr_repositories | jq -r '.hybridrag')"

# 3. ECS service (reads handoff from SM; set handoff_secret_name in 02_app_ecs/terraform.tfvars)
terraform -chdir=02_app_ecs apply
```

`02_app_ecs` needs only `handoff_secret_name = "hybridrag-app"` and `image_tag` when using the SM handoff path. Legacy file handoff via `tfvars_path` is still supported; see the main README.

## Smoke test

```sh
curl -fsS "$(terraform -chdir=01_lz output -json aws | jq -r '.http_edges.main.https_url')/health" | jq .
```

Expect `"status": "healthy"` after Mongo connects and indexes warm up (first boot can take a few minutes).
