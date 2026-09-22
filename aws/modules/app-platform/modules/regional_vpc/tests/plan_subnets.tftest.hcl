mock_provider "aws" {
  mock_data "aws_availability_zones" {
    defaults = { names = ["us-east-1a", "us-east-1b", "us-east-1c"] }
  }
}

variables {
  aws_region = "us-east-1"
  name       = "lz-vpc"
  cidr       = "10.0.0.0/16"
  az_count   = 2
}

run "private_only_by_default" {
  command = plan

  assert {
    condition = alltrue([
      length(output.public_subnets) == 0,
      length(output.natgw_ids) == 0,
    ])
    error_message = "Default VPC should be private-only with no NAT"
  }
}

run "public_subnets_without_nat" {
  command = plan

  variables {
    create_public_subnets = true
  }

  assert {
    condition = alltrue([
      length(output.public_subnets) == 2,
      length(output.natgw_ids) == 0,
    ])
    error_message = "create_public_subnets should add public subnets without NAT"
  }
}

run "nat_creates_public_and_nat" {
  command = plan

  variables {
    enable_nat_gateway = true
  }

  assert {
    condition = alltrue([
      length(output.public_subnets) == 2,
      length(output.natgw_ids) == 1,
    ])
    error_message = "enable_nat_gateway should create public subnets and one NAT (single_nat_gateway default)"
  }
}
