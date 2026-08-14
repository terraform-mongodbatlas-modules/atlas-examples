# `modules/lz`

Example composition: Atlas project, [atlas-aws](https://registry.terraform.io/modules/terraform-mongodbatlas-modules/atlas-aws/mongodbatlas/latest) (PrivateLink, CPA, KMS, log/backup), Atlas cluster, nested VPC, app IAM, ECR, optional HTTP edge (ALB + CloudFront + WAF).

This is not a published Landing Zone product. Nested `regional_vpc` and `http_edge` are implementation details. The module does not create an ECS cluster and does not write the app secret (the example does).

## Inputs callers set

- **`atlas_org_id` / `cluster_name`:** Required.
- **`regions`:** AWS names (`us-east-1`); Atlas `US_EAST_1` is also accepted.
- **`vpc_config`:** `create = true` (default) manages one VPC per cluster AWS region from `base_cidr`. `create = false` requires a full `by_region` entry per region (no hybrid). `ecs_apps.*.internet_egress` turns on NAT in that app region.
- **`http_edges`:** Map of ALB + CloudFront edges. Public subnets are created for those regions. `waf.enabled` defaults true.
- **`ecs_apps`:** Map of ECS targets. Fields: `name`, `ecr_key`, `roles`, `routing` (`edge`, `listener_priority`, `path_pattern` or `host_header`, `container_port`), `internet_egress`. Execution-role `GetSecretValue` is a name glob `secret:<app-name>-app-*`. Task size and health check path are ecs-service inputs, not this type.
- **`ecr_repositories`:** Independent of `ecs_apps` so registries survive compute changes.
- **`cluster_type` / `shard_count`:** Default `SHARDED` / `1`. Set `REPLICASET` for a cheaper lab.
- **`manual_scaling`:** Null keeps compute auto-scaling. Pin `instance_size` (M10 or higher) to disable compute auto-scaling.

Published module schemas: [project](https://registry.terraform.io/modules/terraform-mongodbatlas-modules/project/mongodbatlas/latest), [cluster](https://registry.terraform.io/modules/terraform-mongodbatlas-modules/cluster/mongodbatlas/latest), [atlas-aws](https://registry.terraform.io/modules/terraform-mongodbatlas-modules/atlas-aws/mongodbatlas/latest).

## Outputs

- **`ecs_apps`:** Per-app `network`, `iam`, `mongo`, `routing`, ECR URL, and derived `runtime_secret_name` (`<app-name>-app`). The example stores these groups and passes them to ecs-service. Does not include `ecs_cluster` / `ecs_cluster_arn`, origin-header values, task size, or container env.
- **`http_edge_origin_header_values`:** Sensitive map keyed by `http_edges`. The example copies the value onto `routing.origin_header_value` in the app secret.
- **`atlas.project_id`:** Atlas project ID for example-owned resources in the same project.
- **`ecr_repositories`:** URLs keyed by `ecr_repositories` map key.
- **`aws.http_edges.*.https_url`:** CloudFront HTTPS URL. Smoke tests should not curl the ALB on HTTP.
