# `modules/ecs-service`

ECS cluster, task definition, service, target group, and listener rule. Apply after the image exists.

## Inputs

- **`handoff`:** Decoded lz payload. Required infra fields plus listener priority. Optional fields default in the type (`health_check_path = /health`, `container_port = 8000`, empty path/host/origin). Extra JSON keys are stripped. `secret_arn` is required when `container_secret_keys` is set; task secrets use `valueFrom = "<secret_arn>:<key>::"`. The example app merges the looked-up SM ARN.
- **`image_tag`:** Tag appended to `handoff.ecr_repository_url`.

The example `app/` root reads the SM secret and passes this object. The module does not call Secrets Manager.

The module creates the ECS cluster from `handoff.name`. It does not take a cluster ARN.

Listener rule requires at least one of `path_pattern`, `host_header`, or `origin_header_name`.

## Outputs

- **`index_run`:** `{ aws_region, cluster, service }` for a one-shot `ecs run-task` against this service.
