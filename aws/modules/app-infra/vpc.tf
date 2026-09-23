# VPC, app security groups, and VPC endpoints.

locals {
  ecs_container_ports_by_region = {
    for region in local.ecs_alb_regions : region => distinct([
      for app in local.ecs_routing_apps :
      app.routing.container_port
      if local.http_edges[app.routing.edge].aws_region == region
    ])
  }
  app_regions_with_internet_egress = toset(concat(
    var.vpc_config.enable_nat_gateway ? tolist(local.app_aws_regions) : [],
    tolist(local.ecs_internet_egress_regions)
  ))
}

# --- VPC ----------------------------------------------------------------------
module "vpc" {
  for_each = local.managed_vpc_regions

  source     = "./modules/regional_vpc"
  aws_region = each.key
  name       = "${var.default_resource_name_prefix}-vpc-${each.key}"
  cidr       = local.vpc_cidr_by_region[each.key]
  az_count   = local.vpc_az_count_by_region[each.key]

  enable_nat_gateway = local.enable_nat_gateway_by_region[each.key]
  single_nat_gateway = var.vpc_config.single_nat_gateway
  # VPC origins require an IGW in the VPC even though it does not route origin
  # traffic. create_public_subnets stays false; the ALB is private and subnets
  # come from NAT needs only.
  create_igw            = var.vpc_config.create_igw || contains(local.ecs_alb_regions, each.key)
  create_public_subnets = false
  tags                  = var.tags
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
