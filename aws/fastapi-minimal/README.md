# FastAPI Minimal

Single-region Atlas Landing Zone demo on AWS: private VPC + PrivateLink cluster, then a FastAPI Lambda image that talks to MongoDB over IAM auth.

Layout:

- `01_infra/`: Atlas project, PrivateLink, encryption, log/backup S3, cluster, VPC (private-only + VPC endpoints), Lambda IAM role, IAM DB user
- `02_app_lambda/`: Amazon ECR (or Bring Your Own ECR) + Lambda + Function URL + CloudWatch
- `src/`: FastAPI app (Docker build context for the Lambda image)
- `justfile`: `build-push` only (login + build `linux/arm64` + push)

Run all commands from this directory. Use `terraform -chdir=…` instead of `cd`.

A longer guide covering destroy pitfalls and cost gotchas will land in a follow-up. Custom DNS (Route 53 hostname) is not covered yet.

## Prerequisites

1. Terraform >= 1.10
2. Atlas credentials (prefer service account: `MONGODB_ATLAS_CLIENT_ID` / `MONGODB_ATLAS_CLIENT_SECRET`) with permission to create projects
3. AWS credentials for the target account/region
4. Docker (for `just build-push`)
5. Copy [01_infra/terraform.tfvars.example](./01_infra/terraform.tfvars.example) to `01_infra/terraform.tfvars` and set `atlas_org_id`

Module inputs: [project](https://registry.terraform.io/modules/terraform-mongodbatlas-modules/project/mongodbatlas/latest), [atlas-aws](https://registry.terraform.io/modules/terraform-mongodbatlas-modules/atlas-aws/mongodbatlas/latest), [cluster](https://registry.terraform.io/modules/terraform-mongodbatlas-modules/cluster/mongodbatlas/latest).

## Happy path (create Amazon ECR)

```sh
terraform -chdir=01_infra init
terraform -chdir=01_infra apply

terraform -chdir=02_app_lambda init
terraform -chdir=02_app_lambda apply -target=aws_ecr_repository.app
just build-push
terraform -chdir=02_app_lambda apply

curl "$(terraform -chdir=02_app_lambda output -raw function_url)?write=hello"
aws logs tail "$(terraform -chdir=02_app_lambda output -raw lambda_log_group_name)" --follow
```

`01_infra` apply writes `02_app_lambda/infra.auto.tfvars` by default (gitignored). That file includes the Mongo connection string on disk.

Lambda create fails if the image tag is missing. Always `just build-push` before the full `02_app_lambda` apply.

## Bring Your Own ECR

Set `ecr_repository_url` in `02_app_lambda` (existing repository URL, no tag). Skip `-target`. Push, then apply:

```sh
ECR_REPOSITORY_URL=123456789012.dkr.ecr.us-east-1.amazonaws.com/my-repo just build-push
terraform -chdir=02_app_lambda apply
```

## Handoff

Default path: `01_infra` → `02_app_lambda/infra.auto.tfvars`. Set `app_tfvars = ""` in `01_infra` to disable, then paste values from [02_app_lambda/terraform.tfvars.example](./02_app_lambda/terraform.tfvars.example).

## Networking and IAM

- Private subnets only. No NAT gateway or Internet Gateway by default.
- VPC endpoints: `ecr.api`, `ecr.dkr`, `s3` (gateway), `logs`, `sts` (needed for image pull, logs, and MongoDB IAM auth).
- Lambda security group egress is limited to the VPC CIDR (PrivateLink + interface endpoints) and the S3 prefix list. Add a NAT gateway only if the app needs public internet.
- Atlas IAM database user has `readWrite` on database `test` only. The app uses that database (`DB_NAME` / `app_database_name`).
- Function URL uses `authorization_type = NONE` (anyone with the URL can call it). MongoDB stays private via PrivateLink.

### App env (set by `02_app_lambda`)

- **MONGO_URL**: Private connection string from infra
- **USE_IAM_AUTH**: `true` (rebuilds URI with `MONGODB-AWS` in Lambda)
- **DB_NAME**: Database name (default `test`)

## Destroy

Destroy the app stack before infra. Lambda keeps elastic network interfaces attached to the infra security group until `02_app_lambda` is gone.

```sh
terraform -chdir=02_app_lambda destroy
terraform -chdir=01_infra destroy
```

Things that often block or slow destroy (longer guide coming in a follow-up):

- PrivateLink endpoints and KMS key deletion window
- Log/backup S3 buckets (`s3_force_destroy`, default `true` for demo tear-down; set `false` for shared accounts)
- VPC interface endpoints
- Cluster backups retained by default (`retain_backups_enabled`); snapshots may remain in Atlas after destroy
- Autoscaling max is the cluster module default (M200); watch cost on long-lived accounts
