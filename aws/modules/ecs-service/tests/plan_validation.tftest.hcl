mock_provider "aws" {
  override_during = plan

  mock_data "aws_subnet" {
    defaults = {
      vpc_id = "vpc-mock"
    }
  }
}

variables {
  image_tag          = "0.0.1"
  name               = "hybridrag-ui"
  aws_region         = "us-east-1"
  ecr_repository_url = "123456789012.dkr.ecr.us-east-1.amazonaws.com/hybridrag-ui"
  network = {
    private_subnet_ids    = ["subnet-aaa"]
    ecs_security_group_id = "sg-ecs"
  }
  iam = {
    task_role_arn           = "arn:aws:iam::123456789012:role/task"
    task_execution_role_arn = "arn:aws:iam::123456789012:role/exec"
  }
  routing = {
    listener_arn      = "arn:aws:elasticloadbalancing:us-east-1:123456789012:listener/app/example/abc/def"
    listener_priority = 100
    path_pattern      = ["/*"]
  }
}

run "rejects_empty_private_subnet_ids" {
  command = plan

  variables {
    network = {
      private_subnet_ids    = []
      ecs_security_group_id = "sg-ecs"
    }
  }

  expect_failures = [
    var.network,
  ]
}

run "rejects_listener_rule_without_condition" {
  command = plan

  variables {
    routing = {
      listener_arn      = "arn:aws:elasticloadbalancing:us-east-1:123456789012:listener/app/example/abc/def"
      listener_priority = 100
    }
  }

  expect_failures = [
    var.routing,
  ]
}

run "rejects_origin_header_name_without_value" {
  command = plan

  variables {
    routing = {
      listener_arn       = "arn:aws:elasticloadbalancing:us-east-1:123456789012:listener/app/example/abc/def"
      listener_priority  = 100
      path_pattern       = ["/*"]
      origin_header_name = "X-Origin-Verify"
    }
  }

  expect_failures = [
    var.routing,
  ]
}

run "rejects_secret_keys_without_arn" {
  command = plan

  variables {
    container = {
      secret_keys = ["VOYAGE_API_KEY"]
    }
  }

  expect_failures = [
    var.container,
  ]
}
