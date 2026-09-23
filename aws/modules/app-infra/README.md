# `modules/app-infra`

AWS app infra for an Atlas deployment: managed or BYO VPC, VPC endpoints, app security groups, ECS task and execution roles, ECR, and an optional HTTP edge (ALB + CloudFront + WAF).

This is not a published Landing Zone product. The nested `regional_vpc` and `http_edge` modules are implementation details. The module does not create an ECS cluster, does not write the app secret, and does not touch Atlas. The caller composes the published [project](https://registry.terraform.io/modules/terraform-mongodbatlas-modules/project/mongodbatlas/latest), [atlas-aws](https://registry.terraform.io/modules/terraform-mongodbatlas-modules/atlas-aws/mongodbatlas/latest), and [cluster](https://registry.terraform.io/modules/terraform-mongodbatlas-modules/cluster/mongodbatlas/latest) modules, plus the database users and connection strings, next to this one.

## Inputs callers set

- **`regions`:** AWS names (`us-east-1`); Atlas `US_EAST_1` is also accepted. One VPC per region on the managed path.
- **`vpc_config`:** `create = true` (default) manages one VPC per cluster AWS region from `base_cidr`. `create = false` requires a full `by_region` entry per region (no hybrid). `ecs_apps.*.internet_egress` turns on NAT in that app region. `skip_interface_endpoints` omits AWS interface VPC endpoints (ECR, logs, Secrets Manager, STS) when NAT is on; S3 gateway stays. `bedrock_runtime_endpoint` adds a `bedrock-runtime` interface endpoint with a policy scoped to the Converse and InvokeModel actions, for apps that call Bedrock over the VPC. It bills per AZ-hour and is omitted when `skip_interface_endpoints` is true.
- **`http_edges`:** Map of ALB + CloudFront edges. The ALB is internal in the region's private subnets. CloudFront reaches it through a VPC origin, so only this distribution can reach the app; the ALB security group keeps its ingress from the shared CloudFront origin-facing prefix list, which is account-wide. The edge region gets an IGW (a VPC origin requires one). WAF is on by default; set `waf.disabled = true` to skip. `waf.common_rule_set_count_rules` counts named Common Rule Set rules (empty by default).
- **`ecs_apps`:** Map of ECS targets. Fields: `name`, `ecr_key`, `roles`, `routing` (`edge`, `listener_priority`, `path_pattern` or `host_header`, `container_port`), `internet_egress`, `extra_task_policies`. Execution-role `GetSecretValue` is a name glob `secret:<app-name>-app-*`. Task size and health check path are ecs-service inputs, not this type.
- **`extra_task_policies` (per app):** `map(string)` of policy name to JSON the caller authors. The module attaches each as a task-role policy, so a caller can grant extra AWS actions (for example Bedrock) without writing IAM here.
- **`ecr_repositories`:** Independent of `ecs_apps` so registries survive compute changes.

## Outputs

- **`ecs_apps`:** Per-app `network`, `iam`, `routing`, ECR URL, and derived `runtime_secret_name` (`<app-name>-app`). The caller stores these groups and passes them to ecs-service. The caller owns the database name and connection string. Does not include `ecs_cluster` / `ecs_cluster_arn`, task size, or container env.
- **`region_network`:** Per-cluster-region `vpc_id`, `private_subnet_ids`, and `vpc_cidr_block` for every entry in `regions`, so the caller can wire Atlas PrivateLink endpoints with no dependency cycle.
- **`aws.http_edges.*.https_url`:** CloudFront HTTPS URL. Smoke tests should not curl the ALB directly; the ALB is internal.
- **`ecr_repositories`:** URLs keyed by `ecr_repositories` map key.
- **`operations`:** Cluster region layout and the managed-VPC `vpc_pin` to copy into `vpc_config.by_region` before reordering regions.

## When your VPC differs from the default

- **BYO VPC:** Set `vpc_config.create = false` and give every cluster region a `by_region` entry (see the variable validation for required fields). A BYO VPC that hosts an `http_edges` entry must already have an internet gateway; Terraform cannot create one inside a VPC it does not manage.
- **VPC endpoints:** `aws_vpc_endpoint.interface` and `aws_vpc_endpoint.s3` in `vpc.tf`. Toggle interface endpoints with `vpc_config.skip_interface_endpoints`.
- **App egress:** The `egress` blocks on `aws_security_group.app` in `vpc.tf` (PrivateLink, interface endpoints, DNS, S3, internet via NAT).
- **NAT:** `enable_nat_gateway_by_region` in `main.tf`; `vpc_config.enable_nat_gateway` turns it on everywhere, `ecs_apps.*.internet_egress` per app region.
