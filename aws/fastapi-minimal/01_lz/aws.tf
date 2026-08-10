locals {
  managed_vpc_regions = var.vpc_config.create ? toset(local.aws_regions) : toset([])
  vpc_cidr_by_region = {
    for i, region in local.aws_regions :
    region => coalesce(
      try(var.vpc_config.by_region[region].cidr, null),
      cidrsubnet(var.vpc_config.base_cidr, 8, i)
    )
  }
  vpc_az_count_by_region = {
    for region in local.aws_regions :
    region => coalesce(try(var.vpc_config.by_region[region].az_count, null), var.vpc_config.az_count)
  }
  privatelink_subnet_ids_by_region = var.vpc_config.create ? {
    for region, mod in module.vpc : region => mod.private_subnets
    } : {
    for region, cfg in var.vpc_config.by_region : region => cfg.private_subnet_ids
  }
  vpc_id                  = var.vpc_config.create ? module.vpc[local.aws_region].vpc_id : var.vpc_config.by_region[local.aws_region].vpc_id
  private_subnet_ids      = var.vpc_config.create ? module.vpc[local.aws_region].private_subnets : var.vpc_config.by_region[local.aws_region].private_subnet_ids
  vpc_cidr_block          = var.vpc_config.create ? module.vpc[local.aws_region].vpc_cidr_block : var.vpc_config.by_region[local.aws_region].vpc_cidr_block
  private_route_table_ids = var.vpc_config.create ? module.vpc[local.aws_region].private_route_table_ids : var.vpc_config.by_region[local.aws_region].private_route_table_ids

  app_aws_regions = toset([for app in local.lambda_apps : app.aws_region]) # ECS/EC2 union in follow-up PR
  app_network = {
    for region in local.app_aws_regions : region => {
      vpc_id                  = var.vpc_config.create ? module.vpc[region].vpc_id : var.vpc_config.by_region[region].vpc_id
      private_subnet_ids      = var.vpc_config.create ? module.vpc[region].private_subnets : var.vpc_config.by_region[region].private_subnet_ids
      vpc_cidr_block          = var.vpc_config.create ? module.vpc[region].vpc_cidr_block : var.vpc_config.by_region[region].vpc_cidr_block
      private_route_table_ids = var.vpc_config.create ? module.vpc[region].private_route_table_ids : var.vpc_config.by_region[region].private_route_table_ids
    }
  }

  mongo_private_connection_string = coalesce(
    try(module.atlas_cluster.connection_strings.private_endpoint[0].srv_connection_string, ""),
    try(module.atlas_cluster.connection_strings.private_srv, ""),
    module.atlas_cluster.connection_strings.standard_srv
  )
  mongo_private_connection_strings_by_region = {
    for region in local.app_aws_regions : region => coalesce(
      try([
        for endpoint in module.atlas_cluster.connection_strings.private_endpoint :
        endpoint.srv_connection_string
        if can(regex(region, endpoint.srv_connection_string))
      ][0], ""),
      try(module.atlas_cluster.connection_strings.private_srv, ""),
      module.atlas_cluster.connection_strings.standard_srv
    )
  }

  public_debug_password = var.public_debug_access != null ? coalesce(
    try(var.public_debug_access.password, null),
    try(random_password.public_debug[0].result, null)
  ) : null

  public_debug_connection_string = var.public_debug_access != null ? format(
    "mongodb+srv://%s:%s@%s/?authSource=admin",
    urlencode(var.public_debug_access.username),
    urlencode(local.public_debug_password),
    trimprefix(module.atlas_cluster.connection_strings.standard_srv, "mongodb+srv://")
  ) : null

  app_handoff_payloads = {
    for k, v in local.lambda_apps : k => {
      aws_region                      = v.aws_region
      name_prefix                     = v.name
      private_subnet_ids              = local.app_network[v.aws_region].private_subnet_ids
      lambda_security_group_id        = aws_security_group.lambda[v.aws_region].id
      lambda_execution_role_arn       = aws_iam_role.lambda_exec[k].arn
      mongo_private_connection_string = local.mongo_private_connection_strings_by_region[v.aws_region]
      app_database_name               = v.primary_database
      ecr_repository_url              = aws_ecr_repository.this[v.ecr_key].repository_url
    }
  }
}

module "vpc" {
  for_each = local.managed_vpc_regions

  source     = "./modules/regional_vpc"
  aws_region = each.key
  name       = "${var.default_resource_name_prefix}-vpc-${each.key}"
  cidr       = local.vpc_cidr_by_region[each.key]
  az_count   = local.vpc_az_count_by_region[each.key]

  enable_nat_gateway = var.vpc_config.enable_nat_gateway
  create_igw         = var.vpc_config.create_igw
  tags               = var.tags
}

resource "aws_security_group" "lambda" {
  for_each = local.app_aws_regions

  region      = each.key
  name_prefix = "${var.default_resource_name_prefix}-lambda-"
  description = "Lambda app SG: PrivateLink + VPC endpoint egress only"
  vpc_id      = local.app_network[each.key].vpc_id

  egress {
    description = "Atlas PrivateLink"
    from_port   = 1024
    to_port     = 65535
    protocol    = "tcp"
    cidr_blocks = [local.app_network[each.key].vpc_cidr_block]
  }

  egress {
    description = "VPC interface endpoints HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [local.app_network[each.key].vpc_cidr_block]
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

  tags = merge(var.tags, { Name = "${var.default_resource_name_prefix}-lambda-${each.key}" })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_security_group" "vpc_endpoints" {
  for_each = local.app_aws_regions

  region      = each.key
  name_prefix = "${var.default_resource_name_prefix}-vpce-"
  description = "Interface VPC endpoints for Lambda AWS API access"
  vpc_id      = local.app_network[each.key].vpc_id

  ingress {
    description     = "HTTPS from Lambda"
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = [aws_security_group.lambda[each.key].id]
  }

  tags = merge(var.tags, { Name = "${var.default_resource_name_prefix}-vpce-${each.key}" })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_endpoint" "interface" {
  for_each = {
    for pair in setproduct(tolist(local.app_aws_regions), ["ecr.api", "ecr.dkr", "logs", "sts"]) :
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

  region = each.value.aws_region
  name   = each.value.secret_name
  tags   = var.tags
}

resource "aws_secretsmanager_secret_version" "app" {
  for_each = local.lambda_secrets

  region        = each.value.aws_region
  secret_id     = aws_secretsmanager_secret.app[each.key].id
  secret_string = jsonencode(local.app_handoff_payloads[each.key])
}

resource "local_file" "app_tfvars" {
  for_each = local.lambda_tfvars

  filename = each.value.tfvars_path
  content  = <<-EOT
    aws_region                      = "${local.app_handoff_payloads[each.key].aws_region}"
    name_prefix                     = "${local.app_handoff_payloads[each.key].name_prefix}"
    private_subnet_ids              = ${jsonencode(local.app_handoff_payloads[each.key].private_subnet_ids)}
    lambda_security_group_id        = "${local.app_handoff_payloads[each.key].lambda_security_group_id}"
    lambda_execution_role_arn       = "${local.app_handoff_payloads[each.key].lambda_execution_role_arn}"
    mongo_private_connection_string = "${local.app_handoff_payloads[each.key].mongo_private_connection_string}"
    app_database_name               = "${local.app_handoff_payloads[each.key].app_database_name}"
    ecr_repository_url              = "${local.app_handoff_payloads[each.key].ecr_repository_url}"
  EOT
}
