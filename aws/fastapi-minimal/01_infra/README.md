# FastAPI Minimal — 01_infra

Single-region Atlas Landing Zone stack for the FastAPI demo: project, PrivateLink, encryption, log/backup S3, cluster, VPC (private-only + VPC endpoints), Lambda IAM role, and IAM DB user.

Full SA apply/destroy guide is forthcoming (t16-03). `02_app_lambda` and `src/` are separate tasks.

## Prerequisites

1. Terraform >= 1.10
2. Atlas credentials (prefer service account: `MONGODB_ATLAS_CLIENT_ID` / `MONGODB_ATLAS_CLIENT_SECRET`) with permission to create projects
3. AWS credentials for the target account/region
4. Copy [terraform.tfvars.example](./terraform.tfvars.example) to `terraform.tfvars` and set `atlas_org_id`

Module inputs: [project](https://registry.terraform.io/modules/terraform-mongodbatlas-modules/project/mongodbatlas/latest), [atlas-aws](https://registry.terraform.io/modules/terraform-mongodbatlas-modules/atlas-aws/mongodbatlas/latest), [cluster](https://registry.terraform.io/modules/terraform-mongodbatlas-modules/cluster/mongodbatlas/latest).

## Networking

Private subnets only. No NAT/IGW by default. VPC endpoints: `ecr.api`, `ecr.dkr`, `s3` (gateway), `logs`, `sts`. Lambda SG egress is limited to VPC CIDR (PrivateLink + interface endpoints) and the S3 prefix list.

Add NAT only if the app needs public internet egress.

## Apply / destroy

```sh
terraform init
terraform apply
terraform destroy
```

Destroy pitfalls (see t16-03 for the full runbook):

- PrivateLink endpoints and KMS deletion window
- Log/backup S3 buckets (`s3_force_destroy`, default `true` for demo tear-down; set `false` for shared accounts)
- VPC interface endpoints
- Cluster backups retained by default (`retain_backups_enabled`); snapshots may remain in Atlas after destroy
- Autoscaling max is module default M200; intentional production posture, watch cost

## IAM database privilege

Lambda Atlas user has `readWrite` on database `test` only. The app must use that database (`app_database_name` output).
