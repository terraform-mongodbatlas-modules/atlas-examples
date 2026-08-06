locals {
  az_letters = ["a", "b", "c", "d", "e", "f"]

  vpc_id                  = var.vpc_config.create ? module.vpc[0].vpc_id : var.vpc_config.vpc_id
  private_subnet_ids      = var.vpc_config.create ? module.vpc[0].private_subnets : var.vpc_config.private_subnet_ids
  vpc_cidr_block          = var.vpc_config.create ? module.vpc[0].vpc_cidr_block : var.vpc_config.vpc_cidr_block
  private_route_table_ids = var.vpc_config.create ? module.vpc[0].private_route_table_ids : var.vpc_config.private_route_table_ids

  mongo_private_connection_string = coalesce(
    try(module.atlas_cluster.connection_strings.private_endpoint[0].srv_connection_string, ""),
    try(module.atlas_cluster.connection_strings.private_srv, ""),
    module.atlas_cluster.connection_strings.standard_srv
  )

  app_handoff_payloads = {
    for k, v in local.lambda_apps : k => {
      aws_region                      = local.aws_region
      private_subnet_ids              = local.private_subnet_ids
      lambda_security_group_id        = aws_security_group.lambda.id
      lambda_execution_role_arn       = aws_iam_role.lambda_exec[k].arn
      mongo_private_connection_string = local.mongo_private_connection_string
      app_database_name               = v.primary_database
      ecr_repository_url              = aws_ecr_repository.this[v.ecr_key].repository_url
    }
  }
}

module "vpc" {
  count   = var.vpc_config.create ? 1 : 0
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.21"

  name = "${var.name_prefix}-vpc"
  cidr = var.vpc_config.cidr

  azs             = [for i in range(var.vpc_config.az_count) : "${local.aws_region}${local.az_letters[i]}"]
  private_subnets = [for i in range(var.vpc_config.az_count) : cidrsubnet(var.vpc_config.cidr, 4, i)]

  enable_nat_gateway            = var.vpc_config.enable_nat_gateway
  create_igw                    = var.vpc_config.create_igw
  enable_dns_hostnames          = true
  enable_dns_support            = true
  manage_default_security_group = false
  manage_default_network_acl    = false
  manage_default_route_table    = false

  tags = var.tags
}

resource "aws_security_group" "lambda" {
  name_prefix = "${var.name_prefix}-lambda-"
  description = "Lambda app SG: PrivateLink + VPC endpoint egress only"
  vpc_id      = local.vpc_id

  egress {
    description = "Atlas PrivateLink"
    from_port   = 1024
    to_port     = 65535
    protocol    = "tcp"
    cidr_blocks = [local.vpc_cidr_block]
  }

  egress {
    description = "VPC interface endpoints HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [local.vpc_cidr_block]
  }

  egress {
    description = "VPC DNS"
    from_port   = 53
    to_port     = 53
    protocol    = "udp"
    cidr_blocks = [local.vpc_cidr_block]
  }

  tags = merge(var.tags, { Name = "${var.name_prefix}-lambda" })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_security_group" "vpc_endpoints" {
  name_prefix = "${var.name_prefix}-vpce-"
  description = "Interface VPC endpoints for Lambda AWS API access"
  vpc_id      = local.vpc_id

  ingress {
    description     = "HTTPS from Lambda"
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = [aws_security_group.lambda.id]
  }

  tags = merge(var.tags, { Name = "${var.name_prefix}-vpce" })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_endpoint" "interface" {
  for_each = toset(["ecr.api", "ecr.dkr", "logs", "sts"])

  vpc_id              = local.vpc_id
  service_name        = "com.amazonaws.${local.aws_region}.${each.value}"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = local.private_subnet_ids
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true

  tags = merge(var.tags, { Name = "${var.name_prefix}-${each.value}" })
}

resource "aws_vpc_endpoint" "s3" {
  vpc_id            = local.vpc_id
  service_name      = "com.amazonaws.${local.aws_region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = local.private_route_table_ids

  tags = merge(var.tags, { Name = "${var.name_prefix}-s3" })
}

resource "aws_security_group_rule" "lambda_s3" {
  type              = "egress"
  security_group_id = aws_security_group.lambda.id
  description       = "S3 via gateway VPC endpoint (ECR layers)"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  prefix_list_ids   = [aws_vpc_endpoint.s3.prefix_list_id]
}

resource "aws_iam_role" "lambda_exec" {
  for_each = local.lambda_apps

  name = "${each.value.name}-lambda-exec"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "lambda_exec" {
  for_each = local.lambda_role_policy_attachments

  role       = aws_iam_role.lambda_exec[each.value.app_key].name
  policy_arn = each.value.policy_arn
}

resource "aws_secretsmanager_secret" "app" {
  for_each = local.lambda_secrets

  name = each.value.secret_name
  tags = var.tags
}

resource "aws_secretsmanager_secret_version" "app" {
  for_each = local.lambda_secrets

  secret_id     = aws_secretsmanager_secret.app[each.key].id
  secret_string = jsonencode(local.app_handoff_payloads[each.key])
}

resource "local_file" "app_tfvars" {
  for_each = local.lambda_tfvars

  filename = each.value.tfvars_path
  content  = <<-EOT
    aws_region                      = "${local.app_handoff_payloads[each.key].aws_region}"
    private_subnet_ids              = ${jsonencode(local.app_handoff_payloads[each.key].private_subnet_ids)}
    lambda_security_group_id        = "${local.app_handoff_payloads[each.key].lambda_security_group_id}"
    lambda_execution_role_arn       = "${local.app_handoff_payloads[each.key].lambda_execution_role_arn}"
    mongo_private_connection_string = "${local.app_handoff_payloads[each.key].mongo_private_connection_string}"
    app_database_name               = "${local.app_handoff_payloads[each.key].app_database_name}"
    ecr_repository_url              = "${local.app_handoff_payloads[each.key].ecr_repository_url}"
  EOT
}
