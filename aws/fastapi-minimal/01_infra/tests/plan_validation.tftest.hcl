mock_provider "mongodbatlas" {}
mock_provider "aws" {}

variables {
  atlas_org_id = "org123"
}

run "defaults" {
  command = plan

  assert {
    condition     = local.aws_region == "us-east-1"
    error_message = "US_EAST_1 should derive us-east-1"
  }

  assert {
    condition     = output.atlas_cluster_name == "fastapi-minimal" && output.app_database_name == "test"
    error_message = "Cluster name and app DB should match defaults"
  }

  assert {
    condition     = length(module.vpc.natgw_ids) == 0
    error_message = "NAT should be disabled"
  }

  assert {
    condition     = toset(keys(aws_vpc_endpoint.interface)) == toset(["ecr.api", "ecr.dkr", "logs", "sts"])
    error_message = "Expected interface VPC endpoints for ECR, Logs, STS"
  }

  assert {
    condition     = module.atlas_aws.encryption_at_rest_provider == "AWS"
    error_message = "Encryption should be enabled"
  }

  assert {
    condition = length([
      for r in mongodbatlas_database_user.lambda.roles :
      r if r.role_name == "readWrite" && r.database_name == "test"
    ]) == 1 && length(mongodbatlas_database_user.lambda.roles) == 1
    error_message = "IAM DB user should be readWrite on test only"
  }
}

run "name_prefix_override" {
  command = plan

  variables {
    atlas_org_id = "org123"
    name_prefix  = "demo-app"
    atlas_region = "EU_WEST_1"
  }

  assert {
    condition     = local.aws_region == "eu-west-1" && output.aws_region == "eu-west-1"
    error_message = "EU_WEST_1 should derive eu-west-1"
  }

  assert {
    condition     = output.atlas_cluster_name == "demo-app"
    error_message = "Cluster name should follow name_prefix"
  }
}
