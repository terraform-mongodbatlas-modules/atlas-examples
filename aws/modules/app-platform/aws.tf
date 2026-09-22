data "aws_caller_identity" "current" {}

# --- VPC ----------------------------------------------------------------------
module "vpc" {
  for_each = local.managed_vpc_regions

  source     = "./modules/regional_vpc"
  aws_region = each.key
  name       = "${var.default_resource_name_prefix}-vpc-${each.key}"
  cidr       = local.vpc_cidr_by_region[each.key]
  az_count   = local.vpc_az_count_by_region[each.key]

  enable_nat_gateway    = local.enable_nat_gateway_by_region[each.key]
  single_nat_gateway    = var.vpc_config.single_nat_gateway
  create_igw            = var.vpc_config.create_igw
  create_public_subnets = contains(local.ecs_alb_regions, each.key)
  tags                  = var.tags
}

# --- HTTP edge (ALB + CloudFront + WAF) ---------------------------------------
module "http_edge" {
  for_each = local.http_edges

  source              = "./modules/http_edge"
  aws_region          = each.value.aws_region
  name                = "${var.default_resource_name_prefix}-${each.key}"
  security_group_name = "${var.default_resource_name_prefix}-alb-${each.key}"
  vpc_id              = local.app_network[each.value.aws_region].vpc_id
  public_subnet_ids   = local.app_network[each.value.aws_region].public_subnet_ids
  aliases             = each.value.aliases
  acm_certificate_arn = each.value.acm_certificate_arn
  idle_timeout        = each.value.idle_timeout
  waf                 = each.value.waf
  tags                = var.tags
}

# --- App security groups ------------------------------------------------------
resource "aws_security_group" "app" {
  for_each = local.app_aws_regions

  region      = each.key
  name_prefix = "${var.default_resource_name_prefix}-app-"
  description = "App SG: PrivateLink + VPC endpoint egress"
  vpc_id      = local.app_network[each.key].vpc_id

  dynamic "ingress" {
    for_each = merge([
      for edge_key, edge in local.http_edges : {
        for port in lookup(local.ecs_container_ports_by_region, each.key, []) :
        "${edge_key}-${port}" => {
          port   = port
          alb_sg = module.http_edge[edge_key].alb_security_group_id
        }
        if edge.aws_region == each.key
      }
    ]...)
    content {
      description     = "ECS tasks from HTTP edge ALB"
      from_port       = ingress.value.port
      to_port         = ingress.value.port
      protocol        = "tcp"
      security_groups = [ingress.value.alb_sg]
    }
  }

  egress {
    description = "Atlas PrivateLink"
    from_port   = 1024
    to_port     = 65535
    protocol    = "tcp"
    cidr_blocks = [local.app_network[each.key].vpc_cidr_block]
  }

  dynamic "egress" {
    for_each = var.vpc_config.skip_interface_endpoints ? [] : [1]
    content {
      description = "VPC interface endpoints HTTPS"
      from_port   = 443
      to_port     = 443
      protocol    = "tcp"
      cidr_blocks = [local.app_network[each.key].vpc_cidr_block]
    }
  }

  egress {
    description = "VPC DNS"
    from_port   = 53
    to_port     = 53
    protocol    = "udp"
    cidr_blocks = [local.app_network[each.key].vpc_cidr_block]
  }

  egress {
    description     = "S3 via gateway VPC endpoint (ECR layers)"
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    prefix_list_ids = [aws_vpc_endpoint.s3[each.key].prefix_list_id]
  }

  dynamic "egress" {
    for_each = contains(local.app_regions_with_internet_egress, each.key) ? [1] : []
    content {
      description = "Internet HTTPS via NAT (ecs_apps internet_egress or vpc_config.enable_nat_gateway)"
      from_port   = 443
      to_port     = 443
      protocol    = "tcp"
      cidr_blocks = ["0.0.0.0/0"]
    }
  }

  tags = merge(var.tags, { Name = "${var.default_resource_name_prefix}-app-${each.key}" })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_security_group" "vpc_endpoints" {
  for_each = var.vpc_config.skip_interface_endpoints ? toset([]) : local.app_aws_regions

  region      = each.key
  name_prefix = "${var.default_resource_name_prefix}-vpce-"
  description = "Interface VPC endpoints for ECS AWS API access"
  vpc_id      = local.app_network[each.key].vpc_id

  ingress {
    description     = "HTTPS from app"
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = [aws_security_group.app[each.key].id]
  }

  tags = merge(var.tags, { Name = "${var.default_resource_name_prefix}-vpce-${each.key}" })

  lifecycle {
    create_before_destroy = true
  }
}

# --- VPC endpoints ------------------------------------------------------------
resource "aws_vpc_endpoint" "interface" {
  for_each = var.vpc_config.skip_interface_endpoints ? {} : {
    for pair in concat(
      setproduct(tolist(local.app_aws_regions), ["ecr.api", "ecr.dkr", "logs", "secretsmanager", "sts"]),
      var.vpc_config.bedrock_runtime_endpoint ? setproduct(tolist(local.app_aws_regions), ["bedrock-runtime"]) : []
    ) :
    "${pair[0]}-${pair[1]}" => {
      region  = pair[0]
      service = pair[1]
    }
  }

  region              = each.value.region
  vpc_id              = local.app_network[each.value.region].vpc_id
  service_name        = "com.amazonaws.${each.value.region}.${each.value.service}"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = local.app_network[each.value.region].private_subnet_ids
  security_group_ids  = [aws_security_group.vpc_endpoints[each.value.region].id]
  private_dns_enabled = true

  # VPC endpoint policies are resource-based: Principal is required or the EC2
  # API rejects the document at create time (InvalidPolicyDocument). CountTokens
  # is here because pydantic-ai counts tokens before a request, and
  # GetInferenceProfile because the `us.` inference-profile model ids need it.
  policy = each.value.service == "bedrock-runtime" ? jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = "*"
      Action = [
        "bedrock:InvokeModel",
        "bedrock:InvokeModelWithResponseStream",
        "bedrock:Converse",
        "bedrock:ConverseStream",
        "bedrock:CountTokens",
        "bedrock:GetInferenceProfile",
      ]
      Resource = "*"
    }]
  }) : null

  tags = merge(var.tags, { Name = "${var.default_resource_name_prefix}-${each.value.region}-${each.value.service}" })
}

resource "aws_vpc_endpoint" "s3" {
  for_each = local.app_aws_regions

  region            = each.key
  vpc_id            = local.app_network[each.key].vpc_id
  service_name      = "com.amazonaws.${each.key}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = local.app_network[each.key].private_route_table_ids

  tags = merge(var.tags, { Name = "${var.default_resource_name_prefix}-s3-${each.key}" })

  lifecycle {
    precondition {
      condition     = !var.vpc_config.skip_interface_endpoints || contains(local.app_regions_with_internet_egress, each.key)
      error_message = "vpc_config.skip_interface_endpoints requires NAT (vpc_config.enable_nat_gateway or ecs_apps.*.internet_egress) so tasks can reach AWS APIs."
    }
  }
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
