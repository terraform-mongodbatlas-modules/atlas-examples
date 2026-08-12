# FastAPI Minimal

**Why:** Deploy a production-shaped MongoDB Atlas data plane on AWS with Landing Zone modules (PrivateLink, encryption, logging, backup export) into a reusable `01_lz` base, then prove connectivity with a thin FastAPI Lambda stack.

**Audience (Developer Days):**

- **Platform track (~10):** Own `01_lz` (Atlas + PrivateLink + VPC). Leave with a base you can iterate on for other apps.
- **App track (~100):** Enable an app deployment target, consume LZ handoff, build/push the image, apply thin `02_app_lambda`.

Success bar: both groups leave with something running and a clear next edit.

**What this creates:**

- **Atlas (`01_lz`):** Project, PrivateLink endpoint(s), customer-key encryption-at-rest, log + backup-export integrations, sharded cluster (`SHARDED`, `shard_count = 2` by default)
- **AWS platform (`01_lz`):** PrivateLink VPC endpoint(s), Cloud Provider Access, module-managed KMS CMK, log + backup-export S3 buckets, VPC (create or BYO) per cluster AWS region
- **Optional app targets (`01_lz`):** ECR, Lambda execution roles, Atlas IAM DB users, app security groups + VPC endpoints per distinct app region (enable via **AWS Lambda** or **Amazon ECS** in tfvars)
- **AWS (`02_app_lambda` or `02_app_ecs`):** Lambda Function URL or ECS Fargate + target group/listener rule, CloudWatch (requires app target configured and image pushed)
- **App:** FastAPI image in `src/` (IAM auth to Mongo over PrivateLink)

Clone [atlas-examples](https://github.com/terraform-mongodbatlas-modules/atlas-examples) only. App source is in `src/`. Run all commands from this directory with `terraform -chdir=…` (do not `cd` into the stacks).

```sh
.
├── 00_atlas_ai_keys
│   └── ...
├── 01_lz
│   ├── aws.tf
│   ├── main.tf
│   ├── terraform.tfvars.example
│   ├── versions.tf
│   └── ...
├── 02_app_lambda
│   ├── terraform.tfvars.example
│   └── ...
├── 02_app_ecs
│   ├── terraform.tfvars.example
│   └── ...
├── 02_app_hybridrag_ui
│   ├── terraform.tfvars.example
│   └── ...
├── docs
│   ├── hybridrag-backend.md
│   ├── hybridrag-ui.md
│   └── lz-changes.md
├── justfile
└── src
    └── ...
```

## Before you start

1. [Terraform](https://developer.hashicorp.com/terraform) >= 1.10
2. Atlas credentials (prefer service account: `MONGODB_ATLAS_CLIENT_ID` / `MONGODB_ATLAS_CLIENT_SECRET`) with permission to create projects
3. AWS credentials for the target account/region (AWS CLI for log tail)
4. [Docker](https://docs.docker.com/), [just](https://github.com/casey/just), and [jq](https://jqlang.org/) (region-change commands use jq)

## Make the example your own

```sh
cp 01_lz/terraform.tfvars.example 01_lz/terraform.tfvars
# Edit 01_lz/terraform.tfvars: set atlas_org_id and cluster_name
```

`01_lz` provisions the Atlas + AWS landing zone. App deployment targets are optional and composable; enable only what you need in `terraform.tfvars`.

### AWS Lambda

Uncomment and apply this block for the FastAPI demo path:

```hcl
ecr_repositories = {
  api = {}
}

lambda_apps = {
  api = {
    ecr_key     = "api"
    roles       = [{ database_name = "test" }]
    tfvars_path = "../02_app_lambda/infra.auto.tfvars"
  }
}
```

Re-apply `01_lz` after adding this block before `just build-push` and `02_app_lambda`. Each `lambda_apps` entry creates one IAM execution role and one Atlas IAM database user. Supply at least one `roles` entry; each entry's `role_name` defaults to `readWrite`. See [02_app_lambda](./02_app_lambda/) for the thin app stack.

### Amazon ECS

Uncomment and apply this block for Fargate behind a platform-owned HTTP edge (ALB + CloudFront in `01_lz`; `http_edges` creates public subnets and IGW; no NAT). Public HTTPS uses the default `*.cloudfront.net` domain unless you set `aliases` + `acm_certificate_arn` (us-east-1 ACM).

```hcl
ecr_repositories = {
  api = {}
}

http_edges = {
  main = {}
}

ecs_apps = {
  api = {
    ecr_key     = "api"
    routing     = { edge = "main", path_pattern = ["/*"], listener_priority = 100 }
    roles       = [{ database_name = "test" }]
    tfvars_path = "../02_app_ecs/infra.auto.tfvars"
  }
}
```

Re-apply `01_lz` before `just build-push` and `02_app_ecs`. Each `ecs_apps` entry creates ECS task + execution roles and an Atlas IAM database user bound to the **task role**. Omit `routing` for private ECS tasks (no ALB listener rule). `02_app_ecs` creates the target group and listener rule only. See [02_app_ecs](./02_app_ecs/). `http_edges` adds a small IGW cost per affected region.

For HybridRAG, use SM handoff (`handoff_secret = {}` in `01_lz`; `handoff_secret_name` in `02_app_ecs`), `api_key_secret = {}` for `/v1/*` API key auth, `atlas_ai_model_api_key` for Voyage, and `internet_egress = true` so the task can reach tiktoken and the Voyage API over HTTPS via NAT. See [docs/hybridrag-backend.md](./docs/hybridrag-backend.md). The standalone [00_atlas_ai_keys](./00_atlas_ai_keys/) stack remains for labs that want a separate Voyage key state.

Shared domain (two apps, one edge): one `http_edges` entry and per-app `routing` (path or host rules). Custom hostname: add `aliases` and a us-east-1 `acm_certificate_arn`, then CNAME to `cloudfront_domain` from `terraform output`. See [01_lz/terraform.tfvars.example](./01_lz/terraform.tfvars.example).

### Amazon EC2

TODO: future `ec2_apps` map; no resources in `01_lz` yet (follow-up PR).

### Platform-only landing zone

Valid to apply with no app targets (`ecr_repositories = {}`, `lambda_apps = {}`). You get Atlas + PrivateLink + VPC(s) + Cloud Provider Access/KMS/log/backup only. App teams run their own pipeline and wire compute themselves; run `terraform -chdir=01_lz output` for LZ visibility (each output has a description). Region and VPC edits: [docs/lz-changes.md](./docs/lz-changes.md).

Optional knobs in `terraform.tfvars`: `cluster_name`, `default_resource_name_prefix`, `regions`, `tags`, `atlas_integrations`, `vpc_config`, `cluster_type`, `manual_scaling`, `public_debug_access`.

For a short-lived lab, see [What is the cost of running this example?](#what-is-the-cost-of-running-this-example) (replica-set escape hatch, skip module-managed KMS, and other levers before the first apply).

Toggle encryption, log export, and backup export with `atlas_integrations` in tfvars (defaults keep all three on). Lab snippets: [01_lz/terraform.tfvars.example](./01_lz/terraform.tfvars.example). BYO and shared-account patterns: [What is the cost of running this example?](#what-is-the-cost-of-running-this-example). Pin cluster autoscaling with `manual_scaling`. VPC, security groups, ECR, and the Lambda role live in [01_lz/aws.tf](./01_lz/aws.tf). Full schemas: [project](https://registry.terraform.io/modules/terraform-mongodbatlas-modules/project/mongodbatlas/latest), [atlas-aws](https://github.com/terraform-mongodbatlas-modules/terraform-mongodbatlas-atlas-aws/tree/main), [cluster](https://registry.terraform.io/modules/terraform-mongodbatlas-modules/cluster/mongodbatlas/latest). The `atlas-aws` module temporarily tracks its `main` branch for the AWS provider 6 deprecation fix; switch back to the registry release once that fix is published.

## Handoff to `02_app_lambda`

`01_lz` provisions Atlas, network, IAM, and ECR. `02_app_lambda` is a thin stack that only needs runtime wiring (subnets, security group, execution role, Mongo connection string, database name, image URL). `01_lz` does not deploy Lambda; it hands those values to the app stack.

Pick one handoff path per `lambda_apps` entry:

- **File (FastAPI demo default):** Set `tfvars_path` (for example `../02_app_lambda/infra.auto.tfvars`). Re-apply `01_lz` to write a gitignored auto-vars file consumed by `02_app_lambda` on the next apply.
- **Secrets Manager:** Omit `tfvars_path` and set `handoff_secret = {}` (optional `name`). Re-apply `01_lz` to publish a JSON secret in the app's `aws_region`. Your app stack reads the secret instead of a local file.
- **Manual:** Omit both `tfvars_path` and `handoff_secret`. Copy one app payload from `terraform -chdir=01_lz output -json app_handoff` into [02_app_lambda/terraform.tfvars.example](./02_app_lambda/terraform.tfvars.example) fields.

Each payload includes: `aws_region`, `name_prefix`, `private_subnet_ids`, `lambda_security_group_id`, `lambda_execution_role_arn`, `mongo_private_connection_string`, `app_database_name`, and `ecr_repository_url`. `mongo_private_connection_string` is the PrivateLink SRV with `authSource=$external` and `authMechanism=MONGODB-AWS` query params; the task/Lambda role supplies credentials at connect. HybridRAG can use the same value as `MONGODB_URI`.

After handoff is in place, push an image before `02_app_lambda` apply:

```sh
repo_url="$(terraform -chdir=01_lz output -json ecr_repositories | jq -r '.api')"
just build-push "${repo_url}"
```

`lambda_apps` output lists configured apps and where handoff landed (`tfvars_path` or `handoff_secret_name`). Destroy the app stack before destroying `01_lz` when Secrets Manager handoff is in use.

## Deploy Atlas and AWS LZ

`01_lz` creates the Atlas project/cluster and AWS platform resources. With the **AWS Lambda** block configured, apply also writes `02_app_lambda/infra.auto.tfvars` (gitignored).

```sh
terraform -chdir=01_lz init
terraform -chdir=01_lz apply
```

## Build the image and deploy Lambda

Requires the **AWS Lambda** block in `terraform.tfvars` and a successful `01_lz` apply.

```sh
# Login, build linux/arm64 from src/, tag 0.0.1 (override: tag="0.0.2"), push
# ECR tags are IMMUTABLE by default: bump the tag on every push (or set image_tag_mutability = "MUTABLE").
repo_url="$(terraform -chdir=01_lz output -json ecr_repositories | jq -r '.api')"
just build-push "${repo_url}"
terraform -chdir=02_app_lambda init
# Creates Lambda + Function URL; fails if the image tag is missing. Run just build-push first.
# Keep 02_app_lambda image_tag in sync with the tag you pushed.
terraform -chdir=02_app_lambda apply
```

What the Lambda does: receives HTTP on a Function URL (`authorization_type = NONE`; anyone with the URL can call it), connects to Atlas over PrivateLink with IAM auth (query params in `MONGO_URL` from handoff), and uses database `test` by default. Mongo stays private; the Function URL is the public smoke-test surface.

## Call the app and read logs

```sh
# Expect JSON with "db": true and a populated read_record
curl "$(terraform -chdir=02_app_lambda output -raw function_url)?write=hello"
# Follows /aws/lambda/<app name from lambda_apps>
aws logs tail "$(terraform -chdir=02_app_lambda output -raw lambda_log_group_name)" --follow
```

## Tear down

Destroy the app stack before LZ when Lambda or ECS was deployed. App ENIs stay attached to the LZ security group until `02_app_*` is gone; destroying LZ first hangs or fails on SG/VPC teardown. For ECS, destroy all `02_app_ecs` stacks (listener rules) before `01_lz` (CloudFront + ALB). If an app sets `handoff_secret`, destroy that app stack before destroying `01_lz`.

```sh
terraform -chdir=02_app_lambda destroy   # or 02_app_ecs
terraform -chdir=01_lz destroy
```

## FAQ

### How does the app reach MongoDB?

Private subnets only (no NAT/IGW by default). When `lambda_apps` is non-empty, VPC endpoints cover `ecr.api`, `ecr.dkr`, `s3` (gateway), `logs`, and `sts` per distinct app region. Lambda SG egress is limited to the VPC CIDR and the S3 prefix list. Each `lambda_apps` entry gets its own IAM execution role and Atlas IAM database user. Image registries live in `ecr_repositories` and are selected with `ecr_key`. Env set by `02_app_lambda`: `MONGO_URL` (handoff URI with IAM query params), `DB_NAME` (primary app `primary_database`, default `test`). `02_app_ecs` passes the same handoff string as `MONGO_URL`.

### How do I connect from my laptop?

Apps use PrivateLink + IAM auth from private subnets by default. Laptop access over the public internet is off unless you set `public_debug_access` in `terraform.tfvars` (single IPv4 allowlist + SCRAM user). Use only for short-lived debugging with Compass or `mongosh`; remove the block when done. Your public IP may change; the SCRAM password lives in Terraform state.

Default grant: `readWrite` on database `test` (matches the FastAPI demo). To read and write all databases, set `role_name = "readWriteAnyDatabase"` and `database_name = "admin"`:

```hcl
public_debug_access = {
  ip_address    = "1.2.3.4"  # your public IP; curl -fsS https://ifconfig.me
  database_name = "admin"
  role_name     = "readWriteAnyDatabase"
}
```

Minimal path (demo DB only):

1. Discover your IP: `curl -fsS https://ifconfig.me`
2. Add to `terraform.tfvars`:
   ```hcl
   public_debug_access = { ip_address = "1.2.3.4" }  # your public IP
   ```
3. `terraform -chdir=01_lz apply`
4. Connect: `mongosh "$(terraform -chdir=01_lz output -raw connection_string_public)"` or paste into Compass.
5. Tear down: remove `public_debug_access` and re-apply.

Optional: `username`, `password` (see `terraform.tfvars.example`). Lambda / ECS paths stay on IAM; this user is independent of `lambda_apps`.

### How do I add another Lambda app?

Add a map entry under `lambda_apps` and point `ecr_key` at an `ecr_repositories` entry (create a new registry key first if you need a separate repo). Each Lambda key gets one IAM role and one Atlas IAM DB user. Use multiple `roles` entries when the app needs more than one database:

```hcl
ecr_repositories = {
  api = {}
}

lambda_apps = {
  api = {
    ecr_key     = "api"
    roles       = [{ database_name = "test" }]
    tfvars_path = "../02_app_lambda/infra.auto.tfvars"
  }
  worker = {
    ecr_key     = "api"
    tfvars_path = "../02_app_worker/infra.auto.tfvars"
    handoff_secret      = {}
    roles = [
      { database_name = "jobs" },
      { database_name = "jobs_archive", role_name = "read" },
    ]
  }
}
```

Re-apply `01_lz`, push an image to that repo URL, and point a thin app stack at that URL, role ARN, and `primary_database`.

### How do I grow to a second Atlas region?

See [docs/lz-changes.md](./docs/lz-changes.md) (**Add a cluster region**). Pin VPC CIDRs from `terraform output -json operations | jq '.vpc_pin'` before reordering `regions`.

### How does `01_lz` hand values to `02_app_lambda`?

See [Handoff to `02_app_lambda`](#handoff-to-02_app_lambda). To move from file handoff to Secrets Manager, see [docs/lz-changes.md](./docs/lz-changes.md) (**Move from file handoff to Secrets Manager**).

### What is the cost of running this example?

Defaults favor a production-shaped stack, not a zero-cost lab. Main drivers:

- **Cluster compute:** Default is sharded (`SHARDED`, `shard_count = 2`), which costs more than a single replica set. For a cheap personal lab, set `cluster_type = "REPLICASET"` before the first apply (`shard_count` is ignored). Compute auto-scales M10–M200 by default; pin a size with `manual_scaling = { instance_size = "M10" }` (disk GB auto-scaling stays on either way).
- **Customer-managed KMS:** Enabled by default. Destroy schedules key deletion (`deletion_window_in_days` default 7, AWS max 30); the key can still bill while pending-delete.
- **Log/backup S3 + Atlas backups:** Buckets and `retain_backups_enabled = true` (snapshots may remain after destroy and block recreating the same cluster name until deleted or you change `cluster_name`). `atlas_integrations.s3_force_destroy` defaults to `true` so demo tear-down can empty the buckets.
- **Multi-region VPCs:** Each `regions` entry with default `vpc_config` creates another VPC (distinct `/16` from `base_cidr`). Extra regions add VPC cost; interface endpoints are created only in regions where at least one `lambda_apps` entry sets `aws_region`.

To make a short-lived run more ephemeral before the first apply, disable module-managed CMK in tfvars:

```hcl
atlas_integrations = { encryption = { enabled = false } }
```

Atlas keeps provider-default encryption at rest (no customer-managed KMS key to create or schedule-delete). Keep `encryption_at_rest_provider = module.atlas_aws.encryption_at_rest_provider` on the cluster; with encryption disabled the module outputs `NONE`.

To also turn off log and backup export (cluster PrivateLink stays on):

```hcl
atlas_integrations = {
  encryption      = { enabled = false }
  log_integration = { enabled = false }
  backup_export   = { enabled = false }
}
```

Other `atlas_integrations` patterns before first apply:

- **Skip KMS PrivateLink, keep CMK:** `encryption = { skip_private_endpoints = true }`. Faster lab apply; less private networking. See [atlas-aws encryption docs](https://github.com/terraform-mongodbatlas-modules/terraform-mongodbatlas-atlas-aws/tree/main).
- **BYO KMS:** `encryption = { kms_key_arn = "arn:aws:kms:..." }` (optionally with `skip_private_endpoints = true`). Module-managed `create_kms_key` is ignored when `kms_key_arn` is set. Buckets stay module-managed; this example does not take BYO S3.
- **Shared account:** Raise KMS pending-delete window and retain bucket objects, for example `encryption = { create_kms_key = { deletion_window_in_days = 30 } }` and `s3_force_destroy = false`.
- **Audit-only logs:** Set `log_integration.integrations` to a single `MONGOD_AUDIT` entry.

Optionally set `retain_backups_enabled = false` on the cluster for cleaner destroy. Leave `atlas_integrations.s3_force_destroy = true` (the default) so log/backup buckets delete with the stack.

### Why is `user_agent_extra.example` set?

`01_lz/versions.tf` sets `terraform.provider_meta.mongodbatlas.user_agent_extra.example = "aws-fastapi-minimal"` so we can track usage of this example via Atlas API traffic. You may remove it if you prefer; leaving it helps us see that people run the demo. For feedback, open a GitHub issue on [atlas-examples](https://github.com/terraform-mongodbatlas-modules/atlas-examples) and leave a comment on what worked or what blocked you.

### What is not covered here?

Custom DNS / Route 53, the Industry Solutions AI app (`aws/ai-demo` is a sibling), multi-region E2E apply, EC2 from `ec2_apps`, and index management (this app needs none).
