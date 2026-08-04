mock_provider "aws" {}

variables {
  aws_region                      = "us-east-1"
  private_subnet_ids              = ["subnet-aaa", "subnet-bbb"]
  lambda_security_group_id        = "sg-lambda"
  lambda_execution_role_arn       = "arn:aws:iam::123456789012:role/fastapi-minimal-lambda-exec"
  mongo_private_connection_string = "mongodb+srv://pl-0.example.mongodb.net"
}

run "create_ecr_defaults" {
  command = plan

  assert {
    condition     = local.create_ecr == true && output.ecr_managed == true
    error_message = "Should create ECR when ecr_repository_url is unset"
  }

  assert {
    condition     = length(aws_ecr_repository.app) == 1 && length(aws_ecr_lifecycle_policy.app) == 1
    error_message = "Should create ECR repository and lifecycle policy by default"
  }

  assert {
    condition = alltrue([
      aws_lambda_function.app.environment[0].variables["USE_IAM_AUTH"] == "true",
      aws_lambda_function.app.environment[0].variables["DB_NAME"] == "test",
      aws_lambda_function.app.environment[0].variables["MONGO_URL"] == var.mongo_private_connection_string,
    ])
    error_message = "Lambda env should set USE_IAM_AUTH, DB_NAME, MONGO_URL"
  }

  assert {
    condition = alltrue([
      aws_lambda_function.app.vpc_config[0].security_group_ids == toset([var.lambda_security_group_id]),
      aws_lambda_function.app.vpc_config[0].subnet_ids == toset(var.private_subnet_ids),
    ])
    error_message = "Lambda must reuse infra SG and subnets"
  }

  assert {
    condition     = aws_lambda_function_url.app.authorization_type == "NONE"
    error_message = "Function URL should use NONE auth for demo smoke"
  }

  assert {
    condition     = aws_cloudwatch_log_group.lambda.name == "/aws/lambda/fastapi-minimal"
    error_message = "Log group should follow /aws/lambda/<function_name>"
  }
}

run "byo_ecr" {
  command = plan

  variables {
    ecr_repository_url = "123456789012.dkr.ecr.us-east-1.amazonaws.com/existing-repo"
    image_tag          = "1.2.3"
    app_database_name  = "appdb"
    name_prefix        = "demo-app"
  }

  assert {
    condition     = local.create_ecr == false && output.ecr_managed == false
    error_message = "Should not create ECR when ecr_repository_url is set"
  }

  assert {
    condition     = length(aws_ecr_repository.app) == 0
    error_message = "No ECR repository resource when BYO"
  }

  assert {
    condition     = local.image_uri == "123456789012.dkr.ecr.us-east-1.amazonaws.com/existing-repo:1.2.3"
    error_message = "Image URI should use BYO URL + image_tag"
  }

  assert {
    condition     = aws_lambda_function.app.environment[0].variables["DB_NAME"] == "appdb"
    error_message = "DB_NAME should follow app_database_name"
  }

  assert {
    condition     = aws_cloudwatch_log_group.lambda.name == "/aws/lambda/demo-app"
    error_message = "Log group should follow name_prefix override"
  }
}
