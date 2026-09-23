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

run "igw_without_public_subnets" {
  command = plan

  variables {
    create_igw            = true
    create_public_subnets = false
  }

  assert {
    condition = alltrue([
      length(aws_internet_gateway.standalone) == 1,
      length(output.public_subnets) == 0,
      length(output.natgw_ids) == 0,
    ])
    error_message = "create_igw without NAT or public subnets should still plan a standalone IGW (CloudFront VPC origin requirement)"
  }
}

run "igw_comes_from_public_subnets_when_present" {
  command = plan

  variables {
    create_igw            = true
    create_public_subnets = true
  }

  assert {
    condition = alltrue([
      length(aws_internet_gateway.standalone) == 0,
      length(output.public_subnets) == 2,
    ])
    error_message = "With public subnets the upstream module owns the IGW, so no standalone IGW"
  }
}

run "no_igw_when_not_requested" {
  command = plan

  assert {
    condition     = length(aws_internet_gateway.standalone) == 0
    error_message = "No standalone IGW when create_igw is false"
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
