data "aws_availability_zones" "available" {
  region = var.aws_region
  state  = "available"
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 6.1"

  region = var.aws_region
  name   = var.name
  cidr   = var.cidr

  azs             = slice(data.aws_availability_zones.available.names, 0, min(var.az_count, length(data.aws_availability_zones.available.names)))
  private_subnets = [for i in range(var.az_count) : cidrsubnet(var.cidr, 4, i)]
  public_subnets  = (var.enable_nat_gateway || var.create_public_subnets) ? [for i in range(var.az_count) : cidrsubnet(var.cidr, 4, 8 + i)] : []

  enable_nat_gateway = var.enable_nat_gateway
  single_nat_gateway = var.single_nat_gateway
  # Also true for VPC origin regions (create_igw is set by the caller there).
  create_igw                    = var.create_igw || var.enable_nat_gateway || var.create_public_subnets
  enable_dns_hostnames          = true
  enable_dns_support            = true
  manage_default_security_group = false
  manage_default_network_acl    = false
  manage_default_route_table    = false

  tags = var.tags
}

# The upstream module creates its IGW only alongside public subnets. A CloudFront
# VPC origin needs an IGW as an internet-reachability marker, with no public
# subnets and no routes to it, so create a bare IGW for that case.
locals {
  standalone_igw = var.create_igw && !var.enable_nat_gateway && !var.create_public_subnets
}

resource "aws_internet_gateway" "standalone" {
  count  = local.standalone_igw ? 1 : 0
  region = var.aws_region
  vpc_id = module.vpc.vpc_id
  tags   = merge(var.tags, { Name = var.name })
}
