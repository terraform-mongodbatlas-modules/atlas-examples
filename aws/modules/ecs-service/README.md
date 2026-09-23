# `modules/ecs-service`

ECS cluster, task definition, service, target group, and listener rule. Apply after the image exists.

## Inputs

Groups match `modules/app-infra` `ecs_apps` output. Extra JSON keys never enter this module.

- **`name` / `aws_region` / `ecr_repository_url`:** Cluster and image.
- **`network`:** `private_subnet_ids`, `ecs_security_group_id`.
- **`iam`:** `task_role_arn`, `task_execution_role_arn`.
- **`routing`:** Listener rule and target group. Includes `health_check_path` (default `/health`; example merge; not an lz output).
- **`container`:** Example-owned `env` and `secret_keys`. `secret_arn` is required when `secret_keys` is set. Task secrets use `valueFrom = "<secret_arn>:<key>::"`.
- **`task_cpu` / `task_memory`:** Fargate size. Defaults `512` / `1024`.
- **`image_tag`:** Appended to `ecr_repository_url`.
- **`deployment_*` / `deregistration_delay`:** Rolling deploy settings. Defaults keep the old task serving until the new one is healthy (`minimum_healthy_percent = 100`, `maximum_percent = 200`) and roll back on failure (`deployment_circuit_breaker_enabled` / `_rollback` true). `deregistration_delay` is the target-group drain time in seconds (default 30).

The example `app/` root reads the SM secret and passes these groups. Mongo env names live on `container.env` (for example `MONGODB_URI`, `MONGODB_DATABASE`). The module does not call Secrets Manager.

The module creates the ECS cluster from `name`. It does not take a cluster ARN.

Listener rule requires at least one of `path_pattern` or `host_header`.

## Outputs

- **`index_run`:** `{ aws_region, cluster, service }` for a one-shot `ecs run-task` against this service.
