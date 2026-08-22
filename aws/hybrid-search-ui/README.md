# Hybrid Search UI on AWS

You end with a CloudFront URL and a Chainlit chat that answers from files you uploaded in the browser. Upload runs extract → Voyage `voyage-context-4` auto-chunk/embed → upsert into `chunks`. Each question embeds the query, runs Atlas `$rankFusion` (vector + text pipelines on those chunks), then optionally calls an LLM. Answers list source filenames. The app never sees a public Mongo endpoint. Terraform is two stacks: Landing Zone, then ECS.

The `$rankFusion` pipeline in `src/hybrid_search/search.py` is adapted from [Hybrid-Search-RAG](https://github.com/romiluz13/Hybrid-Search-RAG) (`hybrid_search_with_rank_fusion`, Apache-2.0). The shipped app is the in-example `hybrid_search` package in this directory, not HybridRAG.

## What this creates

- **Atlas:** Project, SHARDED cluster (one shard; compute auto-scaling), PrivateLink, IAM database user for the ECS task role, Voyage AI model API key.
- **AWS:** VPC (private subnets plus NAT and public subnets for the ALB), KMS/log/backup integrations, ECR, ALB + CloudFront + WAF, ECS task and execution roles, Secrets Manager app secret.
- **App:** ECS cluster, Fargate service running the in-example Chainlit image (port 8001), built from this directory's `Dockerfile`. Indexes are a one-shot `ecs run-task` of that same image with `hybrid-search index create`, not a second service.

```sh
aws/hybrid-search-ui/
├── README.md
├── Dockerfile
├── justfile
├── src/hybrid_search/  # in-example Python app
├── scripts/            # seed download (cache/ is gitignored)
├── docker/             # local compose stacks
├── lz/                 # Atlas + AWS infra, Voyage, Chainlit, app secret
└── app/                # ECS cluster + service
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
# just build-push builds the example-root Dockerfile (linux/arm64).
just build-push "$(terraform -chdir=lz output -raw ecr_repository_url)" 0.0.1

cp app/terraform.tfvars.example app/terraform.tfvars
# app_secret_name default is hybrid-search-ui-app (matches lz). task_cpu / task_memory default 1024 / 2048.
terraform -chdir=app init
terraform -chdir=app apply
```

## Create indexes

```sh
# RunTask of the live UI image with command ["hybrid-search", "index", "create"]. Blocks until exit 0.
just index-create
```

The UI task sets `SKIP_INDEX_CREATION=true`, so the first chat does not submit Atlas Search or Vector index creates. `just index-create` runs the same image with `hybrid-search index create`, which always creates indexes even when that env is set. Skipping `just index-create` still leaves a healthy UI that cannot search.

## Download seed files and open the UI

```sh
just seed-download
open "$(terraform -chdir=lz output -raw https_url)"
```

Log in as `demo` with the password from `terraform -chdir=lz output -raw chainlit_demo_password`. Click **Upload documents** or the composer **Ingest** button, then choose files from `scripts/cache/` (NIST PDFs and OWASP markdown). Try:

- What are the four functions of the AI RMF?
- How should we measure generative AI risk?
- What is prompt injection and how do we mitigate it?

The browser tab is **MongoDB AI risk**. Each answer lists source filenames at the bottom (for example `NIST.AI.100-1.pdf`).

NIST PDFs can take several minutes because Voyage embeds every chunk. Progress updates an **Ingest** step in the thread with chunk counts and elapsed time.

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
- **VPC interface endpoints:** Five AWS interface endpoints (ECR API, ECR DKR, CloudWatch Logs, Secrets Manager, STS) bill per AZ-hour in private subnets. About $2.40/day in `us-east-1` with two AZs. Atlas PrivateLink is separate and is not controlled by this knob.
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
- **Skip AWS interface VPC endpoints:** `vpc_config = { skip_interface_endpoints = true }`. Requires NAT (`internet_egress` is already true for this example). AWS API traffic uses public endpoints over NAT; Atlas PrivateLink and the S3 gateway stay.

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

### How do I tune retrieval breadth?

`TOP_K` caps how many chunks `$rankFusion` returns before the LLM answers. The default is **20** (set in lz `llm_container_env` and passed to the ECS task).

To change it on a deployed stack, edit `TOP_K` in `lz/main.tf` `llm_container_env` (or add a tfvars knob if you fork the example), re-apply lz, then re-apply app so the task picks up the new secret. For local Docker, set `TOP_K` in `secrets/.env.local` or compose env.

### Local Docker without ECS

Run `just dump-local-env` (needs `public_debug_access` in lz tfvars) to write gitignored `secrets/.env.local`, then use `docker/docker-compose.local-ui.yml` or `docker-compose.local-ui-atlas.yml`. See `docs/16/p16_hybrid-search-ui-local-docker.md` in the workspace for full steps.

### Why does search fail with `localhost:28000`?

`$rankFusion` runs `$search` on the Atlas cluster. `mongod` then connects to Atlas Search (`mongot`) at `127.0.0.1:28000` on that same node. `HostUnreachable` / connection refused means `mongot` is not listening. The UI is not talking to MongoDB on your laptop, so this is not a failed `MONGODB_URI` load. If Voyage embeddings succeed and this error follows, the URI loaded.

This example does not create dedicated Search Nodes. They are optional production isolation ([Search deployment options](https://www.mongodb.com/docs/search/deployment/deployment-options/)). On M10+ Atlas, including this sharded lab cluster, `mongot` runs next to `mongod` after the first Search or Vector Search index exists.

Confirm `chunks.text_idx` and `chunks.vector_idx` are READY. `just dump-local-env` copies `SKIP_INDEX_CREATION=true` from the ECS secret, so local compose will not create indexes on boot. Run `just index-create` if they were never created, then wait until READY. If they already are READY, `mongot` is down on the cluster (often after a scale or restart). Recreate the indexes or check Atlas Search health.

### What is the app secret name?

Default `app_secret_name` is `hybrid-search-ui-app` (`<ecs_apps.ui.name>-app`). If you change `ecs_apps.ui.name`, set `app_secret_name` in `app/terraform.tfvars` to match before app apply.

### What region does this example use?

This example uses `regions[0]` (default `us-east-1`). The app provider is `us-east-1` to match. There is no app-region knob.

### Where does the LLM secret go?

`just create-llm-secret` defaults `region=us-east-1`. Override if `regions[0]` is not `us-east-1` (for example `just create-llm-secret region=eu-west-1`).

### What is `public_debug_access`?

Opt-in SCRAM plus one IPv4 for laptop `mongosh`, local hybrid-search Docker, or `just dump-local-env`. Not on the happy path. See commented example in `lz/terraform.tfvars.example` or `lz/variables.tf`.

### How do I use a custom domain?

Set `http_edges.main.aliases` and `acm_certificate_arn` (certificate in `us-east-1`). See [`aws/modules/lz`](../modules/lz/README.md). No new example variables.

### What is `user_agent_extra.example`?

`lz/versions.tf` sets `example = "aws-hybrid-search-ui"` so Atlas API traffic from this demo can be distinguished. It is optional tracking. Remove the `provider_meta` block if you do not want it. Open a GitHub issue if something in the walkthrough is wrong.

### Landing Zone module inputs

Full schemas live in the published modules: [project](https://registry.terraform.io/modules/terraform-mongodbatlas-modules/project/mongodbatlas/latest), [cluster](https://registry.terraform.io/modules/terraform-mongodbatlas-modules/cluster/mongodbatlas/latest), [atlas-aws](https://registry.terraform.io/modules/terraform-mongodbatlas-modules/atlas-aws/mongodbatlas/latest). Demo knobs are `atlas_org_id`, `cluster_name`, and the commented examples in `lz/terraform.tfvars.example`. Composition inputs for VPC and ECS apps are in [`aws/modules/lz`](../modules/lz/README.md).
