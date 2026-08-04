# FastAPI Minimal

**Why:** Deploy a production-shaped MongoDB Atlas data plane on AWS with Landing Zone modules: PrivateLink, encryption, logging, and backup export wired into a private VPC, then prove app connectivity with a small FastAPI Lambda. This example shows how to tie Atlas and AWS resources together in one apply path.

**What this creates:**

- **Atlas:** Project, PrivateLink endpoint, customer-key encryption-at-rest config, log + backup-export integrations, M10–M200 autoscaling replica set, IAM database user (`readWrite` on `test`)
- **AWS (infra):** PrivateLink VPC endpoint, Cloud Provider Access, module-managed KMS CMK, log + backup-export S3 buckets, private-only VPC + VPC endpoints, Lambda execution role + restricted security group
- **AWS (app):** ECR (or Bring Your Own ECR), Lambda, Function URL, CloudWatch
- **App:** FastAPI image in `src/` (IAM auth to Mongo over PrivateLink)

Clone [atlas-examples](https://github.com/terraform-mongodbatlas-modules/atlas-examples) only. App source is in `src/`. Run all commands from this directory with `terraform -chdir=…` (do not `cd` into the stacks).

```sh
.
├── 01_infra
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
5. Copy [01_infra/terraform.tfvars.example](./01_infra/terraform.tfvars.example) to `01_infra/terraform.tfvars` and set `atlas_org_id`

Optional knobs in that tfvars file: `atlas_region`, `name_prefix`, `tags`, `s3_force_destroy`.

For a short-lived lab, see [What is the cost of running this example?](#what-is-the-cost-of-running-this-example) (skip the module-managed KMS key and other cost levers before the first apply).

To change Landing Zone features (PrivateLink, encryption, log integration, backup export) or pin cluster autoscaling, edit the module blocks in [01_infra/main.tf](./01_infra/main.tf) (comments show how to disable features). VPC, security groups, and the Lambda role live in [01_infra/aws.tf](./01_infra/aws.tf). Full schemas: [project](https://registry.terraform.io/modules/terraform-mongodbatlas-modules/project/mongodbatlas/latest), [atlas-aws](https://github.com/terraform-mongodbatlas-modules/terraform-mongodbatlas-atlas-aws/tree/main), [cluster](https://registry.terraform.io/modules/terraform-mongodbatlas-modules/cluster/mongodbatlas/latest). The `atlas-aws` module temporarily tracks its `main` branch for the AWS provider 6 deprecation fix; switch back to the registry release once that fix is published.

## Deploy Atlas and AWS infra

`01_infra` creates the Atlas project/cluster and the AWS network/IAM pieces the app needs. On apply it also writes `02_app_lambda/infra.auto.tfvars` (gitignored), including the private Mongo connection string (hostnames only; IAM auth supplies credentials at runtime).

```sh
terraform -chdir=01_infra init
terraform -chdir=01_infra apply
```

## Build the image and deploy Lambda

Lambda needs a container image in ECR before it can create. Default path: create the repo, push from `src/`, then apply the rest.

```sh
terraform -chdir=02_app_lambda init
# Creates ECR so just build-push has a URL (skip -target when using Bring Your Own ECR; see FAQ)
terraform -chdir=02_app_lambda apply -target=aws_ecr_repository.app
# Login, build linux/arm64 from src/, tag 0.0.1 (override: just build-push 0.0.2), push
just build-push
# Creates Lambda + Function URL; fails if the image tag is missing. Run just build-push first.
terraform -chdir=02_app_lambda apply
```

What the Lambda does: receives HTTP on a Function URL (`authorization_type = NONE`; anyone with the URL can call it), connects to Atlas over PrivateLink with IAM auth (`USE_IAM_AUTH=true`), and uses database `test` only. Mongo stays private; the Function URL is the public smoke-test surface.

## Call the app and read logs

```sh
# Expect JSON with "db": true and a populated read_record
curl "$(terraform -chdir=02_app_lambda output -raw function_url)?write=hello"
# Follows /aws/lambda/<name_prefix>
aws logs tail "$(terraform -chdir=02_app_lambda output -raw lambda_log_group_name)" --follow
```

## Tear down

Destroy the app stack before infra. Lambda ENIs stay attached to the infra security group until `02_app_lambda` is gone; destroying infra first hangs or fails on SG/VPC teardown.

```sh
terraform -chdir=02_app_lambda destroy
terraform -chdir=01_infra destroy
```

## FAQ

### How does the app reach MongoDB?

Private subnets only (no NAT/IGW by default). VPC endpoints cover `ecr.api`, `ecr.dkr`, `s3` (gateway), `logs`, and `sts`. Lambda SG egress is limited to the VPC CIDR and the S3 prefix list. The Atlas IAM DB user has `readWrite` on `test` only. Env set by `02_app_lambda`: `MONGO_URL` (private connection string), `USE_IAM_AUTH=true`, `DB_NAME=test`.

### How do I use an existing ECR repository?

Set `ecr_repository_url` in `02_app_lambda` (URL without tag). Skip the `-target` apply. Then:

```sh
ECR_REPOSITORY_URL=123456789012.dkr.ecr.us-east-1.amazonaws.com/my-repo just build-push
terraform -chdir=02_app_lambda apply
```

### How does `01_infra` hand values to `02_app_lambda`?

By default it writes `02_app_lambda/infra.auto.tfvars`. Set `app_tfvars = ""` in `01_infra` to disable, then paste values from [02_app_lambda/terraform.tfvars.example](./02_app_lambda/terraform.tfvars.example). Prefer disabling the writer in shared or CI accounts when the file is unwanted.

### What is the cost of running this example?

Defaults favor a production-shaped stack, not a zero-cost lab. Main drivers:

- **Cluster compute:** Track instance size while the cluster is up. To cap autoscaling, see the `auto_scaling` example in [01_infra/main.tf](./01_infra/main.tf).
- **Customer-managed KMS:** Enabled by default. Destroy schedules key deletion (`deletion_window_in_days` default 7, AWS max 30); the key can still bill while pending-delete.
- **Log/backup S3 + Atlas backups:** Buckets and `retain_backups_enabled = true` (snapshots may remain after destroy and block recreating the same cluster name until deleted or you change `name_prefix`). `s3_force_destroy` defaults to `true` so demo tear-down can empty the buckets.

To make a short-lived run more ephemeral before the first apply, in [01_infra/main.tf](./01_infra/main.tf) disable module-managed CMK encryption:

```hcl
# Atlas keeps provider-default encryption at rest (no customer-managed KMS key to create or schedule-delete).
encryption = { enabled = false }
```

Keep `encryption_at_rest_provider = module.atlas_aws.encryption_at_rest_provider` on the cluster; with encryption disabled the module outputs `NONE`. Optionally set `retain_backups_enabled = false` on the cluster for cleaner destroy. Leave `s3_force_destroy = true` (the tfvars default) so log/backup buckets delete with the stack.

### Why is `user_agent_extra.example` set?

`01_infra/versions.tf` sets `terraform.provider_meta.mongodbatlas.user_agent_extra.example = "aws-fastapi-minimal"` so we can track usage of this example via Atlas API traffic. You may remove it if you prefer; leaving it helps us see that people run the demo. For feedback, open a GitHub issue on [atlas-examples](https://github.com/terraform-mongodbatlas-modules/atlas-examples) and leave a comment on what worked or what blocked you.

### What is not covered here?

Custom DNS / Route 53, the Industry Solutions AI app (`aws/ai-demo` is a sibling), multi-region or non-Lambda compute, and index management (this app needs none).
