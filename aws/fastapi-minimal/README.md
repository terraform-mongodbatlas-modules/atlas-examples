# FastAPI Minimal

**Why:** Deploy a production-shaped MongoDB Atlas data plane on AWS with Landing Zone modules (PrivateLink, encryption, logging, backup export) into a reusable `01_lz` base, then prove connectivity with a thin FastAPI Lambda stack.

**Audience (Developer Days):**

- **Platform track (~10):** Own `01_lz` (Atlas + PrivateLink + VPC + ECR + IAM DB users). Leave with a base you can iterate on for other apps.
- **App track (~100):** Consume LZ outputs (file handoff by default; optional Secrets Manager), build/push the image, apply thin `02_app_lambda`.

Success bar: both groups leave with something running and a clear next edit.

**What this creates:**

- **Atlas:** Project, PrivateLink endpoint(s), customer-key encryption-at-rest, log + backup-export integrations, sharded cluster (`SHARDED`, `shard_count = 2` by default), one IAM database user per `lambda_apps` entry (`roles` default: `readWrite` on `test`)
- **AWS (`01_lz`):** PrivateLink VPC endpoint(s), Cloud Provider Access, module-managed KMS CMK, log + backup-export S3 buckets, VPC (create or BYO) + VPC endpoints, `ecr_repositories` (independent of compute), one Lambda execution role per `lambda_apps` entry, shared Lambda security group
- **AWS (`02_app_lambda`):** Lambda, Function URL, CloudWatch (requires ECR URL from LZ)
- **App:** FastAPI image in `src/` (IAM auth to Mongo over PrivateLink)

Clone [atlas-examples](https://github.com/terraform-mongodbatlas-modules/atlas-examples) only. App source is in `src/`. Run all commands from this directory with `terraform -chdir=…` (do not `cd` into the stacks).

```sh
.
├── 01_lz
│   ├── aws.tf
│   ├── main.tf
│   ├── terraform.tfvars.example
│   ├── versions.tf
│   └── ...
├── 02_app_lambda
│   ├── terraform.tfvars.example
│   └── ...
├── justfile
└── src
    └── ...
```

## Before you start

1. [Terraform](https://developer.hashicorp.com/terraform) >= 1.10
2. Atlas credentials (prefer service account: `MONGODB_ATLAS_CLIENT_ID` / `MONGODB_ATLAS_CLIENT_SECRET`) with permission to create projects
3. AWS credentials for the target account/region (AWS CLI for log tail)
4. [Docker](https://docs.docker.com/) and [just](https://github.com/casey/just)
5. Copy [01_lz/terraform.tfvars.example](./01_lz/terraform.tfvars.example) to `01_lz/terraform.tfvars` and set `atlas_org_id`

Optional knobs in that tfvars file: `regions`, `name_prefix`, `tags`, `s3_force_destroy`, `ecr_repositories`, `lambda_apps` (per-app `tfvars_path` / `secret`), `vpc_config`, `cluster_type`, `manual_scaling`.

For a short-lived lab, see [What is the cost of running this example?](#what-is-the-cost-of-running-this-example) (replica-set escape hatch, skip module-managed KMS, and other levers before the first apply).

To change Landing Zone features (PrivateLink, encryption, log integration, backup export) or pin cluster autoscaling, edit the module blocks in [01_lz/main.tf](./01_lz/main.tf) (comments show how to disable features). VPC, security groups, ECR, and the Lambda role live in [01_lz/aws.tf](./01_lz/aws.tf). Full schemas: [project](https://registry.terraform.io/modules/terraform-mongodbatlas-modules/project/mongodbatlas/latest), [atlas-aws](https://github.com/terraform-mongodbatlas-modules/terraform-mongodbatlas-atlas-aws/tree/main), [cluster](https://registry.terraform.io/modules/terraform-mongodbatlas-modules/cluster/mongodbatlas/latest). The `atlas-aws` module temporarily tracks its `main` branch for the AWS provider 6 deprecation fix; switch back to the registry release once that fix is published.

## Deploy Atlas and AWS LZ

`01_lz` creates the Atlas project/cluster, AWS network/IAM, and ECR. On apply it writes `02_app_lambda/infra.auto.tfvars` (gitignored), including the private Mongo connection string (hostnames only; IAM auth supplies credentials at runtime) and `ecr_repository_url`.

```sh
terraform -chdir=01_lz init
terraform -chdir=01_lz apply
```

## Build the image and deploy Lambda

LZ already created ECR. Build/push, then apply the thin app stack.

```sh
# Login, build linux/arm64 from src/, tag 0.0.1 (override: just build-push 0.0.2), push
# ECR tags are IMMUTABLE by default: bump the tag on every push (or set image_tag_mutability = "MUTABLE").
just build-push
terraform -chdir=02_app_lambda init
# Creates Lambda + Function URL; fails if the image tag is missing. Run just build-push first.
# Keep 02_app_lambda image_tag in sync with the tag you pushed.
terraform -chdir=02_app_lambda apply
```

What the Lambda does: receives HTTP on a Function URL (`authorization_type = NONE`; anyone with the URL can call it), connects to Atlas over PrivateLink with IAM auth (`USE_IAM_AUTH=true`), and uses database `test` by default. Mongo stays private; the Function URL is the public smoke-test surface.

## Call the app and read logs

```sh
# Expect JSON with "db": true and a populated read_record
curl "$(terraform -chdir=02_app_lambda output -raw function_url)?write=hello"
# Follows /aws/lambda/<name_prefix>
aws logs tail "$(terraform -chdir=02_app_lambda output -raw lambda_log_group_name)" --follow
```

## Tear down

Destroy the app stack before LZ. Lambda ENIs stay attached to the LZ security group until `02_app_lambda` is gone; destroying LZ first hangs or fails on SG/VPC teardown. If an app sets `secret`, destroy that app stack before destroying `01_lz` (secrets are deleted with LZ).

```sh
terraform -chdir=02_app_lambda destroy
terraform -chdir=01_lz destroy
```

## FAQ

### How does the app reach MongoDB?

Private subnets only (no NAT/IGW by default). VPC endpoints cover `ecr.api`, `ecr.dkr`, `s3` (gateway), `logs`, and `sts`. Lambda SG egress is limited to the VPC CIDR and the S3 prefix list. Each `lambda_apps` entry gets its own IAM execution role and Atlas IAM database user (`roles` map to `mongodbatlas_database_user.roles`; `role_name` defaults to `readWrite`). Image registries live in `ecr_repositories` and are selected with `ecr_key` (not destroyed when you remove a Lambda app). Env set by `02_app_lambda`: `MONGO_URL` (private connection string), `USE_IAM_AUTH=true`, `DB_NAME` (primary app `primary_database`, default `test`).

### How do I add another Lambda app?

Add a map entry under `lambda_apps` and point `ecr_key` at an `ecr_repositories` entry (create a new registry key first if you need a separate repo). Each Lambda key gets one IAM role and one Atlas IAM DB user. Use multiple `roles` entries when the app needs more than one database:

```hcl
ecr_repositories = {
  api = {}
}

lambda_apps = {
  default = {
    ecr_key     = "api"
    roles       = [{ database_name = "test" }]
    tfvars_path = "../02_app_lambda/infra.auto.tfvars"
  }
  worker = {
    ecr_key     = "api"
    tfvars_path = "../02_app_worker/infra.auto.tfvars"
    secret      = {}
    roles = [
      { database_name = "jobs" },
      { database_name = "jobs_archive", role_name = "read" },
    ]
  }
}
```

Re-apply `01_lz`, push an image to that repo URL, and point a thin app stack at that URL, role ARN, and `primary_database`. `ecs_apps` is a stub (`default = {}`) with no resources yet; when it lands it should reuse `ecr_key`, `tfvars_path`, and `secret` the same way.

### How do I grow to a second Atlas region?

Add another object to `regions` (same shape as the [cluster module](https://registry.terraform.io/modules/terraform-mongodbatlas-modules/cluster/mongodbatlas/latest)). `01_lz` creates module-managed PrivateLink for each unique `regions[*].name`. With default `vpc_config.create = true`, Terraform also creates one private VPC per cluster AWS region and wires subnets into PrivateLink; append to `regions` only (west gets `10.1.0.0/16` from `base_cidr` by default). Override a region with `vpc_config.by_region[region].cidr` or `az_count`. For full BYO, set `create = false` and populate `by_region` for every cluster AWS region. Lambda, ECR, and interface VPC endpoints stay in `regions[0]` only. Architecture Center: put a private endpoint in every region where the cluster is deployed ([network security](https://www.mongodb.com/docs/atlas/architecture/current/network-security/)).

### How does `01_lz` hand values to `02_app_lambda`?

By default the `default` lambda app writes `02_app_lambda/infra.auto.tfvars` via `tfvars_path` (includes that app’s `ecr_repository_url` and role ARN). Omit `tfvars_path` on an app to skip its file writer, then paste values from [02_app_lambda/terraform.tfvars.example](./02_app_lambda/terraform.tfvars.example).

Optional Secrets Manager: set `secret = {}` (or `secret = { name = "..." }`) on that app when the app track should not read Terraform state. Re-apply `01_lz` to replace the secret version (no automatic rotator in this demo). Destroy the app stack before deleting the secret / destroying `01_lz`.

### What is the cost of running this example?

Defaults favor a production-shaped stack, not a zero-cost lab. Main drivers:

- **Cluster compute:** Default is sharded (`SHARDED`, `shard_count = 2`), which costs more than a single replica set. For a cheap personal lab, set `cluster_type = "REPLICASET"` before the first apply (`shard_count` is ignored). Compute auto-scales M10–M200 by default; pin a size with `manual_scaling = { instance_size = "M10" }` (disk GB auto-scaling stays on either way).
- **Customer-managed KMS:** Enabled by default. Destroy schedules key deletion (`deletion_window_in_days` default 7, AWS max 30); the key can still bill while pending-delete.
- **Log/backup S3 + Atlas backups:** Buckets and `retain_backups_enabled = true` (snapshots may remain after destroy and block recreating the same cluster name until deleted or you change `name_prefix`). `s3_force_destroy` defaults to `true` so demo tear-down can empty the buckets.
- **Multi-region VPCs:** Each `regions` entry with default `vpc_config` creates another VPC (distinct `/16` from `base_cidr`). Extra regions add VPC cost; interface endpoints are not created outside `regions[0]`.

To make a short-lived run more ephemeral before the first apply, in [01_lz/main.tf](./01_lz/main.tf) disable module-managed CMK encryption:

```hcl
# Atlas keeps provider-default encryption at rest (no customer-managed KMS key to create or schedule-delete).
encryption = { enabled = false }
```

Keep `encryption_at_rest_provider = module.atlas_aws.encryption_at_rest_provider` on the cluster; with encryption disabled the module outputs `NONE`. Optionally set `retain_backups_enabled = false` on the cluster for cleaner destroy. Leave `s3_force_destroy = true` (the tfvars default) so log/backup buckets delete with the stack.

### Why is `user_agent_extra.example` set?

`01_lz/versions.tf` sets `terraform.provider_meta.mongodbatlas.user_agent_extra.example = "aws-fastapi-minimal"` so we can track usage of this example via Atlas API traffic. You may remove it if you prefer; leaving it helps us see that people run the demo. For feedback, open a GitHub issue on [atlas-examples](https://github.com/terraform-mongodbatlas-modules/atlas-examples) and leave a comment on what worked or what blocked you.

### What is not covered here?

Custom DNS / Route 53, the Industry Solutions AI app (`aws/ai-demo` is a sibling), multi-region E2E apply, regional Lambda/ECR, ECS from `ecs_apps`, and index management (this app needs none).
