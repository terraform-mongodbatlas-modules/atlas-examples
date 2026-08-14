# `modules/ecs-service`

ECS cluster, task definition, service, target group, and listener rule. Apply after the image exists.

## Inputs

Groups match `modules/lz` `ecs_apps` output. Extra JSON keys never enter this module.

- **`name` / `aws_region` / `ecr_repository_url`:** Cluster and image.
- **`network`:** `private_subnet_ids`, `ecs_security_group_id`.
- **`iam`:** `task_role_arn`, `task_execution_role_arn`.
- **`routing`:** Listener rule and target group. Includes `health_check_path` (default `/health`) and `origin_header_value` (example merge; not an lz output).
- **`container`:** Example-owned `env` and `secret_keys`. `secret_arn` is required when `secret_keys` is set. Task secrets use `valueFrom = "<secret_arn>:<key>::"`.
- **`task_cpu` / `task_memory`:** Fargate size. Defaults `512` / `1024`.
- **`image_tag`:** Appended to `ecr_repository_url`.

The example `app/` root reads the SM secret and passes these groups. Mongo env names live on `container.env` (for example `MONGODB_URI`, `MONGODB_DATABASE`). The module does not call Secrets Manager.

The module creates the ECS cluster from `name`. It does not take a cluster ARN.

Listener rule requires at least one of `path_pattern`, `host_header`, or `origin_header_name`.

## Outputs

- **`index_run`:** `{ aws_region, cluster, service }` for a one-shot `ecs run-task` against this service.
