locals {
  aws_region = replace(lower(var.atlas_region), "_", "-")

  mongo_private_connection_string = coalesce(
    try(module.atlas_cluster.connection_strings.private_endpoint[0].srv_connection_string, ""),
    try(module.atlas_cluster.connection_strings.private_srv, ""),
    module.atlas_cluster.connection_strings.standard_srv
  )
  app_database_name = one([for r in mongodbatlas_database_user.lambda.roles : r.database_name])
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.21"

  name = "${var.name_prefix}-vpc"
  cidr = "10.0.0.0/16"

  # Plan-time AZs (a/b); add NAT/IGW only if the app later needs public internet egress.
  azs             = ["${local.aws_region}a", "${local.aws_region}b"]
  private_subnets = [for i in range(2) : cidrsubnet("10.0.0.0/16", 4, i)]

  enable_nat_gateway            = false
  create_igw                    = false
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
  vpc_id      = module.vpc.vpc_id

  egress {
    description = "Atlas PrivateLink"
    from_port   = 1024
    to_port     = 65535
    protocol    = "tcp"
    cidr_blocks = [module.vpc.vpc_cidr_block]
  }

  egress {
    description = "VPC interface endpoints HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [module.vpc.vpc_cidr_block]
  }

  egress {
    description = "VPC DNS"
    from_port   = 53
    to_port     = 53
    protocol    = "udp"
    cidr_blocks = [module.vpc.vpc_cidr_block]
  }

  tags = merge(var.tags, { Name = "${var.name_prefix}-lambda" })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_security_group" "vpc_endpoints" {
  name_prefix = "${var.name_prefix}-vpce-"
  description = "Interface VPC endpoints for Lambda AWS API access"
  vpc_id      = module.vpc.vpc_id

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

  vpc_id              = module.vpc.vpc_id
  service_name        = "com.amazonaws.${local.aws_region}.${each.value}"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = module.vpc.private_subnets
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true

  tags = merge(var.tags, { Name = "${var.name_prefix}-${each.value}" })
}

resource "aws_vpc_endpoint" "s3" {
  vpc_id            = module.vpc.vpc_id
  service_name      = "com.amazonaws.${local.aws_region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = module.vpc.private_route_table_ids

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
  name = "${var.name_prefix}-lambda-exec"

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
  for_each = {
    basic = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
    vpc   = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
    ecr   = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  }

  role       = aws_iam_role.lambda_exec.name
  policy_arn = each.value
}

resource "local_file" "app_tfvars" {
  count    = var.app_tfvars != "" ? 1 : 0
  filename = var.app_tfvars
  content  = <<-EOT
    aws_region                      = "${local.aws_region}"
    private_subnet_ids              = ${jsonencode(module.vpc.private_subnets)}
    lambda_security_group_id        = "${aws_security_group.lambda.id}"
    lambda_execution_role_arn       = "${aws_iam_role.lambda_exec.arn}"
    mongo_private_connection_string = "${local.mongo_private_connection_string}"
    app_database_name               = "${local.app_database_name}"
  EOT
}
