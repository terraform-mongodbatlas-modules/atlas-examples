# `modules/ecs-service`

ECS cluster, task definition, service, target group, and listener rule. Apply after the image exists.

## Inputs

- **`handoff_secret_name`:** Secrets Manager secret written by the example lz stack. The JSON supplies VPC, roles, ECR URL, routing, origin header, and `container_secret_keys`.
- **`image_tag`:** Tag to append to the handoff `ecr_repository_url`.

The module creates the ECS cluster and names it from the handoff `name`. It does not read a cluster ARN from the secret.

Task secrets use `valueFrom = "<handoff-arn>:<key>::"` for each entry in `container_secret_keys`. Health check defaults to `/health` when the handoff omits `health_check_path`.

## Outputs

- **`index_run`:** `{ aws_region, cluster, service }` for a one-shot `ecs run-task` against this service.
