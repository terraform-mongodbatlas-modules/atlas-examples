# Atlas AI Model API keys

Creates a project-scoped Voyage key (`al-...`) billed on the Atlas project invoice. Use with HybridRAG as `VOYAGE_API_KEY` and `VOYAGE_BASE_URL` (MongoDB-hosted endpoint).

Atlas credentials: same as `01_lz` (`MONGODB_ATLAS_CLIENT_ID` / `MONGODB_ATLAS_CLIENT_SECRET` or provider defaults).

**Provider:** `mongodbatlas_ai_model_api_key` ships in mongodbatlas provider **2.16+** (not yet on the public registry; use provider `master` via `dev_overrides` until release). `01_lz` can stay on `~> 2.15`.

## Apply order

1. `terraform -chdir=01_lz apply` — read `project_id` from `terraform output -json atlas | jq -r .project_id`
2. `cp 00_atlas_ai_keys/terraform.tfvars.example 00_atlas_ai_keys/terraform.tfvars` and set `project_id`
3. `terraform -chdir=00_atlas_ai_keys init && terraform -chdir=00_atlas_ai_keys apply`
4. HybridRAG image + `02_app_ecs` (t16-22) — pass Voyage env from handoff or outputs

## Handoff

- **File (lab):** set `output_path = "../secrets/voyage.auto.tfvars.json"` in tfvars. Re-apply writes gitignored JSON:

  ```json
  {
    "voyage_api_key": "<al-...>",
    "voyage_base_url": "https://<endpoint>/v1"
  }
  ```

- **Manual:** `terraform -chdir=00_atlas_ai_keys output -raw ai_model_api_key_secret` (prints secret)

Keep this stack separate from `01_lz` state. Destroy here before destroying the Atlas project if you want the key removed.

## Import

Import format: `PROJECT_ID/API_KEY_ID`. Imported keys have `secret = null`; create a new key via Terraform if you need the secret.

## Smoke test

```sh
terraform -chdir=00_atlas_ai_keys output ai_model_api_key_id
# Secret (prints to terminal):
terraform -chdir=00_atlas_ai_keys output -raw ai_model_api_key_secret
```
