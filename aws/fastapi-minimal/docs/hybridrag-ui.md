# HybridRAG Chainlit UI (ECS)

Browser chat surface for [Hybrid-Search-RAG](https://github.com/EspenAlbert/Hybrid-Search-RAG) on ECS. The UI is a peer service to the API: both connect to MongoDB directly (not HTTP client of the API). See [hybridrag-backend.md](hybridrag-backend.md) for API deploy and [README](../README.md) for Landing Zone setup.

## Prerequisites

- `01_lz` applied with both `ecs_apps.hybridrag` and `ecs_apps.hybridrag_ui` (see `01_lz/terraform.tfvars.example`).
- API image pushed and `02_app_ecs` applied first (indexes warm up on first boot).
- Fork image: `just build-push-ui` (not `docker/Dockerfile.hybridrag`; build context is the fork under `.vendor/`).

## Deploy

```sh
# 1. Landing zone (both apps in one apply)
terraform -chdir=01_lz apply

# 2. Images
just build-push-backend "$(terraform -chdir=01_lz output -json ecr_repositories | jq -r '.hybridrag')"
just build-push-ui "$(terraform -chdir=01_lz output -json ecr_repositories | jq -r '.hybridrag_ui')"

# 3. ECS services (order does not matter for Terraform state)
terraform -chdir=02_app_ecs apply
terraform -chdir=02_app_hybridrag_ui apply
```

`02_app_hybridrag_ui` needs only `handoff_secret_name = "hybridrag-ui-app"` and `image_tag`.

## Login

When `chainlit_auth_secret` and `ui_demo_credentials` are set on the UI `ecs_apps` entry, Chainlit shows a password login form.

- Username: plain env `CHAINLIT_DEMO_USERNAME` (default `demo` in tfvars example).
- Password: SM secret (default name `hybridrag-ui-demo-password`).

```sh
aws secretsmanager get-secret-value \
  --secret-id hybridrag-ui-demo-password \
  --query SecretString --output text
```

## Smoke test

```sh
BASE="$(terraform -chdir=01_lz output -json aws | jq -r '.http_edges.main.https_url')"
open "${BASE}/"   # login form, then chat
```

The UI supports ingest and chat (not query-only). PDF upload in chat needs the larger task size (`task_memory = "2048"` in the example).

## Routing

API paths (`/health`, `/v1/*`, `/docs*`) use listener priority 100. UI catch-all `/*` on port 8001 uses priority 200.
