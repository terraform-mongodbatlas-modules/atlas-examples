# Prerequisite networking for the AWS example's E2E runs — NOT a copy of the
# example. See e2e/network-bootstrap/README.md for why this exists and how to
# keep it in sync with the example's inputs.
data "aws_availability_zones" "available" {
  state = "available"
}

resource "aws_vpc" "this" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "atlas-examples-e2e-${var.name_suffix}"
  }
}

# Two private subnets in different AZs, as required for PrivateLink endpoint placement
resource "aws_subnet" "private" {
  count = 2

  vpc_id            = aws_vpc.this.id
  cidr_block        = cidrsubnet(aws_vpc.this.cidr_block, 8, count.index + 1)
  availability_zone = data.aws_availability_zones.available.names[count.index]

  tags = {
    Name = "atlas-examples-e2e-private-${count.index + 1}-${var.name_suffix}"
  }
}
