# HybridRAG UI on AWS

You end with a CloudFront URL and a chat that answers from files you uploaded. Hybrid search runs in Atlas. The app never sees a public Mongo endpoint. Terraform is two stacks: Landing Zone, then ECS.

## What this creates

- **Atlas:** Project, SHARDED cluster (one shard; compute auto-scaling), PrivateLink, IAM database user for the ECS task role, Voyage AI model API key.
- **AWS:** VPC (private subnets plus NAT and public subnets for the ALB), KMS/log/backup integrations, ECR, ALB + CloudFront + WAF, ECS task and execution roles, Secrets Manager app secret.
- **App:** ECS cluster, Fargate service running the HybridRAG UI image (`production-ui`, port 8001). Indexes are a one-shot `ecs run-task` of that same image, not a second service.

App code is [HybridRAG](https://github.com/romiluz13/Hybrid-Search-RAG) (Apache-2.0). This example clones a pin of [this fork](https://github.com/EspenAlbert/Hybrid-Search-RAG): `production-ui` image, Chainlit password auth, and `hybridrag index create` that waits until search indexes are READY.

```sh
aws/hybridrag-ui/
├── README.md
├── justfile
├── lz/                 # Atlas + AWS infra, Voyage, Chainlit, app secret
└── app/                # ECS cluster + service
aws/hybridrag-seed/     # download.py + urls.yaml
aws/modules/lz/
aws/modules/ecs-service/
```

## Before you start

You need Terraform >= 1.9, mongodbatlas `~> 2.16`, [just](https://github.com/casey/just), Docker, AWS and Atlas credentials, and `uv` (seed download only).

Copy tfvars, then set `atlas_org_id` and `cluster_name`:

```sh
cp lz/terraform.tfvars.example lz/terraform.tfvars
```

This stack costs money while it is up (NAT, auto-scaling cluster, WAF). See [How much does this cost?](#how-much-does-this-cost).

## Deploy Atlas and AWS infra

```sh
# Recommended if you will show the UI to someone. Prints a secret name; paste it into lz/terraform.tfvars as llm_secret_name.
just create-llm-secret

# Creates the project, cluster, VPC, CloudFront, IAM, ECR, Voyage key, and nested app secret JSON.
terraform -chdir=lz init
terraform -chdir=lz apply
```

## Build the image and deploy the UI

```sh
# ECR is IMMUTABLE: bump image_tag in app/terraform.tfvars and the tag argument on every push.
just build-push "$(terraform -chdir=lz output -raw ecr_repository_url)" 0.0.1

cp app/terraform.tfvars.example app/terraform.tfvars
# app_secret_name default is hybridrag-ui-app (matches lz). task_cpu / task_memory default 1024 / 2048.
terraform -chdir=app init
terraform -chdir=app apply
```

## Create indexes

```sh
# RunTask of the live UI image with command ["hybridrag", "index", "create"]. Blocks until exit 0.
just index-create
```

The UI task sets `SKIP_INDEX_CREATION=true`, so the first chat does not submit Atlas Search or Vector index creates. `just index-create` runs the same image with `hybridrag index create`, which always creates indexes even when that env is set. Skipping `just index-create` still leaves a healthy UI that cannot search.

## Download seed files and open the UI

```sh
just seed-download
open "$(terraform -chdir=lz output -raw https_url)"
```

Log in as `demo` with the password from `terraform -chdir=lz output -raw chainlit_demo_password`. Upload files from `aws/hybridrag-seed/cache/` (NIST PDFs and OWASP markdown). Try:

- What are the four functions of the AI RMF?
- How should we measure generative AI risk?
- What is prompt injection and how do we mitigate it?

The browser tab is **MongoDB AI risk**. Each answer lists source filenames at the bottom (for example `NIST.AI.100-1.pdf`).

NIST PDFs take several minutes because entity extract runs per chunk. The UI shows `Chunk N of M` and a live elapsed time. A second upload while that runs is queued, not complete.

## Tear down

Destroy the app stack first (ECS ENIs hold the infra security group), then lz:

```sh
terraform -chdir=app destroy
terraform -chdir=lz destroy
```

## FAQ

### How much does this cost?

The following stay billed while the stack is up:

- **NAT Gateway:** Hourly plus data. This example sets `internet_egress = true` so Voyage (and an optional LLM) can reach the internet. Leave NAT on for the walkthrough.
- **Atlas cluster:** Default is a sharded cluster (one shard) with compute auto-scaling from M10 to M200. Disk GB auto-scales either way.
- **KMS, log export, backup export:** On by default via `atlas_integrations`. A customer-managed key has a monthly charge and a pending-delete window after destroy. Log and backup export create S3 buckets.
- **CloudFront WAF:** AWS Managed Rules Common Rule Set, about $6/month if you leave the stack up.
- **ALB, CloudFront, ECS Fargate, ECR, Secrets Manager:** Smaller while you run the lab.

Destroy `app`, then `lz`, when you are done. Leftover cost after a failed destroy is usually Secrets Manager secrets, ECR images, or a KMS key still in pending-delete.

Set the following in `lz/terraform.tfvars` before the first apply (commented copies live in `lz/terraform.tfvars.example`):

- **Replica set:** `cluster_type = "REPLICASET"`.
- **Cap compute:** `manual_scaling = { instance_size = "M10" }`. Disk GB still auto-scales.
- **Skip module-managed CMK, log export, and backup export:** Atlas still encrypts the cluster with provider-default encryption.

```hcl
atlas_integrations = {
  encryption      = { enabled = false }
  log_integration = { enabled = false }
  backup_export   = { enabled = false }
}
```

- **Skip WAF:** `http_edges = { main = { waf = { enabled = false } } }`. Do not use this to unblock Chainlit uploads or WebSockets; see [How do I turn WAF off?](#how-do-i-turn-waf-off) and [What is the file upload size limit?](#what-is-the-file-upload-size-limit).

### How do I turn WAF off?

Set `http_edges = { main = { waf = { enabled = false } } }` in lz tfvars. Do not use this as the WebSocket workaround; if Common Rule Set blocks the Chainlit upgrade, add an allow rule instead. File uploads are a different rule (`SizeRestrictions_BODY`); see [What is the file upload size limit?](#what-is-the-file-upload-size-limit).

### What is the file upload size limit?

AWS WAF Common Rule Set rule `SizeRestrictions_BODY` blocks request bodies larger than 8 KB. Chainlit `POST /project/file` is a multipart upload, so the seed PDFs (about 1-2 MB) return HTTP 403 unless that rule is counted.

This example counts `SizeRestrictions_BODY` and the other Common Rule Set BODY rules (`CrossSiteScripting_BODY`, `GenericRFI_BODY`, `GenericLFI_BODY`, `EC2MetaDataSSRF_BODY`) so PDFs and markdown with URLs are not blocked. Header, query, and path CRS rules still apply.

WAF inspects at most 16 KB of the body on CloudFront (64 KB if you raise the inspection limit). That is inspection only, not an upload size cap. After the BODY rules are counted, CloudFront and the ALB forward the full POST. CloudFront's request-body quota is 64 GB. This example does not set a smaller cap. A slow upload can still fail the 120s origin read timeout.

Do not set `waf.enabled = false` to fix uploads.

### How do I add an LLM key?

The deploy step runs `just create-llm-secret` before `lz apply`. It writes a Secrets Manager secret and prints the name. Set `llm_secret_name` in lz tfvars. Skip the recipe for search-only (`ENABLE_LLM=false`). If you add a key after the first apply, re-apply lz before `just build-push`.

The key is inlined as `llm_env_name` (default `ANTHROPIC_API_KEY`). `LLM_PROVIDER` is inferred from that name (`ANTHROPIC_API_KEY` -> `anthropic`, same for `OPENAI_API_KEY`, `GEMINI_API_KEY`, `GROVE_API_KEY`). Pin the model in `llm_env` (`ANTHROPIC_MODEL`, `GEMINI_MODEL`, `OPENAI_MODEL`, `GROVE_MODEL`). Grove also needs `GROVE_BASE_URL`. OpenAI extras (`OPENAI_BASE_URL`, `OPENAI_EXTRA_HEADERS`) go in `llm_env` too. Commented examples are in `lz/terraform.tfvars.example`.

### Why is each chat answer slow?

The deployed UI defaults to **`mix` query mode** with **`DEFAULT_TOP_K=60`**. That runs local graph search, global graph search, hybrid chunk search, and naive vector search in one pass, then reranks dozens of chunks with Voyage before the LLM answers. A single question can take **1–2 minutes** on a cold path (embeddings, graph fan-out, rerank, LLM).

In the chat UI you can switch mode without redeploying: `/mode hybrid` (vector + keyword fusion) or `/mode naive` (vector only). Type `/faq` in Chainlit for the full in-app guide.

### How do I tune query performance?

Set **`rag_performance`** in `lz/terraform.tfvars` before `lz apply` (or change it and re-apply to refresh the app secret container env). Values are passed to the ECS task as environment variables.

**Defaults (production-shaped quality):**

- `default_query_mode = "mix"`
- `default_top_k = 60`
- `default_rerank_top_k = 10`
- `enable_rerank = true`
- `enable_entity_boosting = true`
- `enable_implicit_expansion = true`

**Faster demo (lower latency, less graph coverage):**

```hcl
rag_performance = {
  default_query_mode        = "hybrid"
  default_top_k             = 20
  default_rerank_top_k      = 5
  enable_rerank             = true
  enable_entity_boosting    = false
  enable_implicit_expansion = false
}
```

**Fastest smoke test (vector search only):**

```hcl
rag_performance = {
  default_query_mode        = "naive"
  default_top_k             = 10
  default_rerank_top_k      = 3
  enable_rerank             = false
  enable_entity_boosting    = false
  enable_implicit_expansion = false
}
```

**Field to env var mapping:**

- **`default_query_mode`** → `DEFAULT_QUERY_MODE`: retrieval strategy (`mix`, `hybrid`, `naive`, `local`, `global`, `bypass`)
- **`default_top_k`** → `DEFAULT_TOP_K`: graph and entity fan-out before reranking
- **`default_rerank_top_k`** → `DEFAULT_RERANK_TOP_K`: chunks kept after Voyage rerank
- **`enable_rerank`** → `ENABLE_RERANK`: Voyage rerank pass
- **`enable_entity_boosting`** → `ENABLE_ENTITY_BOOSTING`: entity overlap boost after rerank
- **`enable_implicit_expansion`** → `ENABLE_IMPLICIT_EXPANSION`: pre-retrieval entity expansion

`/mode` in Chainlit overrides the mode for the current session only. `rag_performance` sets the startup default for new chats.

For local Docker (no ECS), run `just dump-local-env` (needs `public_debug_access` in lz tfvars) or copy `docker/.env.local.example` in the HybridRAG fork. See `docs/16/p16_hybridrag-ui-local-docker.md` in the workspace.

### What is the app secret name?

Default `app_secret_name` is `hybridrag-ui-app` (`<ecs_apps.ui.name>-app`). If you change `ecs_apps.ui.name`, set `app_secret_name` in `app/terraform.tfvars` to match before app apply.

### What region does this example use?

This example uses `regions[0]` (default `us-east-1`). The app provider is `us-east-1` to match. There is no app-region knob.

### Where does the LLM secret go?

`just create-llm-secret` defaults `region=us-east-1`. Override if `regions[0]` is not `us-east-1` (for example `just create-llm-secret region=eu-west-1`).

### What is `public_debug_access`?

Opt-in SCRAM plus one IPv4 for laptop `mongosh`, local HybridRAG Docker, or `just dump-local-env`. Not on the happy path. See commented example in `lz/terraform.tfvars.example` or `lz/variables.tf`.

### How do I use a custom domain?

Set `http_edges.main.aliases` and `acm_certificate_arn` (certificate in `us-east-1`). See [`aws/modules/lz`](../modules/lz/README.md). No new example variables.

### What is `user_agent_extra.example`?

`lz/versions.tf` sets `example = "aws-hybridrag-ui"` so Atlas API traffic from this demo can be distinguished. It is optional tracking. Remove the `provider_meta` block if you do not want it. Open a GitHub issue if something in the walkthrough is wrong.

### Landing Zone module inputs

Full schemas live in the published modules: [project](https://registry.terraform.io/modules/terraform-mongodbatlas-modules/project/mongodbatlas/latest), [cluster](https://registry.terraform.io/modules/terraform-mongodbatlas-modules/cluster/mongodbatlas/latest), [atlas-aws](https://registry.terraform.io/modules/terraform-mongodbatlas-modules/atlas-aws/mongodbatlas/latest). Demo knobs are `atlas_org_id`, `cluster_name`, and the commented examples in `lz/terraform.tfvars.example`. Composition inputs for VPC and ECS apps are in [`aws/modules/lz`](../modules/lz/README.md).
