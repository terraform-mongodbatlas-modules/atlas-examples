# Landing zone changes

Use-case index for editing `01_lz` after the first apply. Config lives in [terraform.tfvars.example](../01_lz/terraform.tfvars.example) and [README](../README.md). LZ visibility: `terraform -chdir=01_lz output` (descriptions on each output).

- [Change the primary region](#change-the-primary-region)
- [Add a cluster region](#add-a-cluster-region)
- [Remove a cluster region](#remove-a-cluster-region)
- [Place compute in another region](#place-compute-in-another-region)
- [Add another Lambda app](#add-another-lambda-app)
- [Run platform-only (no app targets)](#run-platform-only-no-app-targets)
- [App config overlays](#app-config-overlays)
- [Move from file handoff to Secrets Manager](#move-from-file-handoff-to-secrets-manager)
- [ECS HTTP edge tear-down](#ecs-http-edge-tear-down)
- [ECS smoke test URL](#ecs-smoke-test-url)

## Change the primary region

Move a different AWS region to `regions[0]` (default AWS provider region, `operations.regions[0]`, default ECR/Lambda region). Managed VPC CIDRs follow list index unless pinned in `vpc_config.by_region`; pin before reordering `regions`.

1. `terraform -chdir=01_lz output -json operations | jq '.vpc_pin'`
2. Paste each entry into `vpc_config.by_region` in `terraform.tfvars`. Do not paste `aws.vpcs`; it is read-only.
3. Reorder `regions` so the new primary is first
4. `terraform -chdir=01_lz plan` then apply

## Add a cluster region

Grow from one region to multi-region Atlas + managed VPC. Pin existing VPC CIDRs before appending so list index does not reassign them.

1. `terraform -chdir=01_lz output -json operations | jq '.vpc_pin'`
2. Paste each entry into `vpc_config.by_region` in `terraform.tfvars`
3. Append the new region to `regions`
4. Assign a CIDR for the new region in `vpc_config.by_region`, or accept the next auto index
5. Plan and apply. Put a private endpoint in every cluster region ([Architecture Center network security](https://www.mongodb.com/docs/atlas/architecture/current/network-security/))

## Remove a cluster region

Shrink the cluster and tear down that region's VPC. If survivors move index in `regions`, pin their CIDRs in `vpc_config.by_region` first.

1. When list order changes: `terraform -chdir=01_lz output -json operations | jq '.vpc_pin'`, then paste into `vpc_config.by_region`
2. Remove the region from `regions`
3. Plan and apply. Expect Atlas node removal and VPC destroy for that region

## Place compute in another region

Point `lambda_apps.*.aws_region` and matching `ecr_repositories.*.region` at a non-primary cluster region. Both must match. See README **AWS Lambda**. ECS/EC2 placement follows the same pattern when those targets land.

## Add another Lambda app

See README **AWS Lambda** and `terraform.tfvars.example` (multiple `lambda_apps` entries, shared or separate `ecr_repositories` keys).

## Run platform-only (no app targets)

Apply `01_lz` with empty `ecr_repositories`, `lambda_apps`, `ecs_apps`, and `ec2_apps`. You get Atlas + PrivateLink + VPC(s) + CPA/KMS/log/backup only.

App teams supply their own Atlas IAM DB users, compute IAM roles, registry, security groups, VPC endpoints, and `02_app_*` wiring. Run `terraform -chdir=01_lz output` for LZ visibility; runtime handoff is not written unless you configure an app target. For short-lived public debugging, see README FAQ **How do I connect from my laptop?**

## App config overlays

TODO: optional YAML file paths for large `*_apps` maps (follow-up PR).

## Move from file handoff to Secrets Manager

Set `handoff_secret = {}` (or `handoff_secret = { name = "..." }`) on a `lambda_apps` entry. Re-apply `01_lz` to write the secret version. Destroy the app stack before destroying `01_lz` when secrets are in use.

## ECS HTTP edge tear-down

Destroy order when `http_edges` is configured:

1. Destroy `02_app_ecs` stacks (removes listener rules and target groups).
2. Destroy `01_lz` (CloudFront distribution, then ALB).

CloudFront distributions can take several minutes on first deploy and destroy. `01_lz` apply waits for the distribution to deploy before completing.

## ECS smoke test URL

Default HTTPS URL (no custom domain):

```sh
curl -fsS "$(terraform -chdir=01_lz output -json aws | jq -r '.http_edges.main.https_url')/"
```

With `aliases`, `https_url` uses the first alias. Point DNS (CNAME) at `cloudfront_domain` from the same output.
