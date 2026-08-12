mock_provider "aws" {
  override_during = plan
  mock_data "aws_subnet" {
    defaults = {
      vpc_id = "vpc-mock"
    }
  }
  mock_data "aws_secretsmanager_secret_version" {
    defaults = {
      secret_string = jsonencode({
        aws_region                      = "us-east-1"
        name_prefix                     = "hybridrag"
        private_subnet_ids              = ["subnet-aaa", "subnet-bbb"]
        ecs_security_group_id           = "sg-ecs"
        ecs_task_role_arn               = "arn:aws:iam::123456789012:role/hybridrag-ecs-task"
        ecs_task_execution_role_arn     = "arn:aws:iam::123456789012:role/hybridrag-ecs-exec"
        mongo_private_connection_string = "mongodb+srv://pl-0.example.mongodb.net/?authSource=%24external&authMechanism=MONGODB-AWS"
        app_database_name               = "hybridrag"
        ecr_repository_url              = "123456789012.dkr.ecr.us-east-1.amazonaws.com/hybridrag"
        alb_listener_arn                = "arn:aws:elasticloadbalancing:us-east-1:123456789012:listener/app/example/abc/def"
        alb_dns_name                    = "example-123.us-east-1.elb.amazonaws.com"
        listener_priority               = 100
        path_pattern                    = ["/*"]
        container_port                  = 8000
        health_check_path               = "/health"
        container_env_vars = {
          MONGODB_URI      = "mongodb+srv://pl-0.example.mongodb.net/?authSource=%24external&authMechanism=MONGODB-AWS"
          MONGODB_DATABASE = "hybridrag"
          ENABLE_LLM       = "false"
          VOYAGE_BASE_URL  = "https://voyage.example.mongodb.com/v1"
        }
        container_secret_env_vars = {
          VOYAGE_API_KEY = "arn:aws:secretsmanager:us-east-1:123456789012:secret:hybridrag-voyage"
        }
      })
    }
  }
}

run "handoff_secret_consumer" {
  command = plan

  variables {
    handoff_secret_name = "hybridrag-app"
    image_tag           = "0.0.1"
  }

  assert {
    condition = alltrue([
      local.aws_region == "us-east-1",
      local.health_check_path == "/health",
      local.container_env_vars["ENABLE_LLM"] == "false",
      length(local.container_secret_env_vars) == 1,
      aws_lb_target_group.this.health_check[0].path == "/health",
    ])
    error_message = "SM handoff should populate locals and task wiring"
  }
}

run "legacy_flat_variables" {
  command = plan

  variables {
    aws_region                      = "us-east-1"
    private_subnet_ids              = ["subnet-aaa", "subnet-bbb"]
    ecs_security_group_id           = "sg-ecs"
    ecs_task_role_arn               = "arn:aws:iam::123456789012:role/fastapi-minimal-ecs-task"
    ecs_task_execution_role_arn     = "arn:aws:iam::123456789012:role/fastapi-minimal-ecs-exec"
    mongo_private_connection_string = "mongodb+srv://pl-0.example.mongodb.net/?authSource=%24external&authMechanism=MONGODB-AWS"
    ecr_repository_url              = "123456789012.dkr.ecr.us-east-1.amazonaws.com/fastapi-minimal"
    alb_listener_arn                = "arn:aws:elasticloadbalancing:us-east-1:123456789012:listener/app/example/abc/def"
    alb_dns_name                    = "example-123.us-east-1.elb.amazonaws.com"
    listener_priority               = 100
    path_pattern                    = ["/*"]
  }

  assert {
    condition = alltrue([
      aws_lb_target_group.this.port == 8000,
      aws_lb_listener_rule.this.priority == 100,
      aws_ecs_service.this.launch_type == "FARGATE",
    ])
    error_message = "Legacy flat-variable path should still plan"
  }
}

run "missing_handoff_and_flat_vars" {
  command = plan

  variables {
    handoff_secret_name             = null
    aws_region                      = null
    private_subnet_ids              = null
    ecs_security_group_id           = null
    ecs_task_role_arn               = null
    ecs_task_execution_role_arn     = null
    mongo_private_connection_string = null
    ecr_repository_url              = null
    alb_listener_arn                = null
    alb_dns_name                    = null
    listener_priority               = null
  }

  expect_failures = [
    var.handoff_secret_name,
  ]
}
