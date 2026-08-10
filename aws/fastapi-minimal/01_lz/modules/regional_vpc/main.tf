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
  public_subnets  = var.enable_nat_gateway ? [for i in range(var.az_count) : cidrsubnet(var.cidr, 4, 8 + i)] : []

  enable_nat_gateway            = var.enable_nat_gateway
  create_igw                    = var.create_igw || var.enable_nat_gateway
  enable_dns_hostnames          = true
  enable_dns_support            = true
  manage_default_security_group = false
  manage_default_network_acl    = false
  manage_default_route_table    = false

  tags = var.tags
}
