locals {
  az_letters = ["a", "b", "c", "d", "e", "f"]
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 6.1"

  region = var.aws_region
  name   = var.name
  cidr   = var.cidr

  azs             = [for i in range(var.az_count) : "${var.aws_region}${local.az_letters[i]}"]
  private_subnets = [for i in range(var.az_count) : cidrsubnet(var.cidr, 4, i)]

  enable_nat_gateway            = var.enable_nat_gateway
  create_igw                    = var.create_igw
  enable_dns_hostnames          = true
  enable_dns_support            = true
  manage_default_security_group = false
  manage_default_network_acl    = false
  manage_default_route_table    = false

  tags = var.tags
}
