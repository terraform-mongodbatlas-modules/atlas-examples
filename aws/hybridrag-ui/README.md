# HybridRAG UI on AWS

Deploys a browser HybridRAG chat UI against a MongoDB Atlas cluster and AWS Landing Zone defaults: PrivateLink, a managed VPC, and CloudFront in front of ECS. Voyage embeddings are created in this example. An LLM key is optional.

## What this creates

- **Atlas:** Project, SHARDED cluster (one shard; compute auto-scaling), PrivateLink, IAM database user for the ECS task role, Voyage AI model API key.
- **AWS:** VPC (private subnets plus NAT and public subnets for the ALB), KMS/log/backup integrations, ECR, ALB + CloudFront + WAF, ECS task and execution roles, Secrets Manager handoff.
- **App:** ECS cluster, Fargate service running the HybridRAG UI image (`production-ui`, port 8001). Indexes are a one-shot `ecs run-task` of that same image, not a second service.

This repository is Terraform and recipes. The UI image is cloned at build from a pinned [HybridRAG fork](https://github.com/EspenAlbert/Hybrid-Search-RAG).

```sh
aws/hybridrag-ui/
├── README.md
├── justfile
├── lz/                 # Atlas + AWS infra, Voyage, Chainlit, handoff secret
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

This stack costs money while it is up (NAT, auto-scaling cluster, WAF). See [How much does this cost?](#how-much-does-this-cost). Optional LLM is [step 0](#how-do-i-add-an-llm-key).

## Deploy Atlas and AWS infra

```sh
# Creates the project, cluster, VPC, CloudFront, IAM, ECR, Voyage key, Chainlit secrets, and handoff JSON.
terraform -chdir=lz init
terraform -chdir=lz apply
```

## Build the image and deploy the UI

```sh
# Clones the pinned fork, builds --target production-ui (linux/arm64), pushes to ECR.
just build-push "$(terraform -chdir=lz output -raw ecr_repository_url)"

cp app/terraform.tfvars.example app/terraform.tfvars
# handoff_secret_name default is hybridrag-ui-app (matches lz).
terraform -chdir=app init
terraform -chdir=app apply
```

## Create indexes

```sh
# RunTask of the live UI image with command ["hybridrag", "index", "create"]. Blocks until exit 0.
just index-create
```

## Download seed files and open the UI

```sh
just seed-download
open "$(terraform -chdir=lz output -raw https_url)"
```

Log in as `demo` with the password from `terraform -chdir=lz output -raw chainlit_demo_password`. Upload files from `aws/hybridrag-seed/cache/` (NIST PDFs and OWASP markdown). Try:

- What are the four functions of the AI RMF?
- How should we measure generative AI risk?
- What is prompt injection and how do we mitigate it?

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

- **Skip WAF:** `http_edges = { main = { waf = { enabled = false } } }`. Do not use this as the Chainlit WebSocket workaround; see [How do I turn WAF off?](#how-do-i-turn-waf-off).

### How do I turn WAF off?

Set `http_edges = { main = { waf = { enabled = false } } }` in lz tfvars. Do not use this as the WebSocket workaround; if Common Rule Set blocks the Chainlit upgrade, add an allow rule instead.

### How do I add an LLM key?

`just create-llm-secret` writes a Secrets Manager secret and prints the name. Set `llm_secret_name` in lz tfvars and re-apply lz before `just build-push`. Skip this for search-only (`ENABLE_LLM=false`).

The key is inlined as `llm_env_name` (default `ANTHROPIC_API_KEY`). `LLM_PROVIDER` is inferred from that name (`ANTHROPIC_API_KEY` -> `anthropic`, same for `OPENAI_API_KEY`, `GEMINI_API_KEY`, `GROVE_API_KEY`). Grove needs `llm_env.GROVE_BASE_URL`. OpenAI extras (`OPENAI_MODEL`, `OPENAI_BASE_URL`, `OPENAI_EXTRA_HEADERS`) also go in `llm_env`. Commented examples are in `lz/terraform.tfvars.example`.

### What is `user_agent_extra.example`?

`lz/versions.tf` sets `example = "aws-hybridrag-ui"` so Atlas API traffic from this demo can be distinguished. It is optional tracking. Remove the `provider_meta` block if you do not want it. Open a GitHub issue if something in the walkthrough is wrong.

### Landing Zone module inputs

Full schemas live in the published modules: [project](https://registry.terraform.io/modules/terraform-mongodbatlas-modules/project/mongodbatlas/latest), [cluster](https://registry.terraform.io/modules/terraform-mongodbatlas-modules/cluster/mongodbatlas/latest), [atlas-aws](https://registry.terraform.io/modules/terraform-mongodbatlas-modules/atlas-aws/mongodbatlas/latest). Demo knobs are `atlas_org_id`, `cluster_name`, and the commented examples in `lz/terraform.tfvars.example`. Composition inputs for VPC and ECS apps are in [`aws/modules/lz`](../modules/lz/README.md).
