# ECS task and execution roles, their policies, and the locals only they read.

data "aws_caller_identity" "current" {}

locals {
  # --- IAM --------------------------------------------------------------------
  ecs_execution_managed_policies = {
    execution = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
  }
  ecs_execution_role_policy_attachments = {
    for pair in setproduct(keys(local.ecs_apps), keys(local.ecs_execution_managed_policies)) :
    "${pair[0]}-${pair[1]}" => {
      app_key    = pair[0]
      policy_arn = local.ecs_execution_managed_policies[pair[1]]
    }
  }

  # Caller-owned task-role policies (for example Bedrock). The caller passes
  # module.llm.task_policy_jsons through ecs_apps.*.extra_task_policies.
  extra_task_policies = merge([
    for k, v in var.ecs_apps : {
      for name, policy in v.extra_task_policies :
      "${k}-${name}" => { app_key = k, name = name, policy = policy }
    }
  ]...)
}

# --- ECS task and execution roles --------------------------------------------
resource "aws_iam_role" "ecs_task" {
  for_each = local.ecs_apps

  name = "${each.value.name}-ecs-task"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
    }]
  })

  tags = var.tags
}

resource "aws_iam_role" "ecs_task_execution" {
  for_each = local.ecs_apps

  name = "${each.value.name}-ecs-exec"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
    }]
  })

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution" {
  for_each = local.ecs_execution_role_policy_attachments

  role       = aws_iam_role.ecs_task_execution[each.value.app_key].name
  policy_arn = each.value.policy_arn
}

resource "aws_iam_role_policy" "ecs_task_execution_secrets" {
  for_each = local.ecs_apps

  name = "${each.key}-ecs-exec-secrets"
  role = aws_iam_role.ecs_task_execution[each.key].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["secretsmanager:GetSecretValue"]
      Resource = "arn:aws:secretsmanager:${each.value.aws_region}:${data.aws_caller_identity.current.account_id}:secret:${each.value.runtime_secret_name}-*"
    }]
  })
}

# Caller-owned task-role policies (for example Bedrock). The caller authors the
# JSON; this module only attaches it, so the caller does not write IAM here.
resource "aws_iam_role_policy" "extra" {
  for_each = local.extra_task_policies

  name   = each.value.name
  role   = aws_iam_role.ecs_task[each.value.app_key].id
  policy = each.value.policy
}
