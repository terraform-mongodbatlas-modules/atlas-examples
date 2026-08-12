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
        name_prefix                     = "hybridrag-ui"
        private_subnet_ids              = ["subnet-aaa", "subnet-bbb"]
        ecs_security_group_id           = "sg-ecs"
        ecs_task_role_arn               = "arn:aws:iam::123456789012:role/hybridrag-ui-ecs-task"
        ecs_task_execution_role_arn     = "arn:aws:iam::123456789012:role/hybridrag-ui-ecs-exec"
        mongo_private_connection_string = "mongodb+srv://pl-0.example.mongodb.net/?authSource=%24external&authMechanism=MONGODB-AWS"
        app_database_name               = "hybridrag"
        ecr_repository_url              = "123456789012.dkr.ecr.us-east-1.amazonaws.com/hybridrag-ui"
        alb_listener_arn                = "arn:aws:elasticloadbalancing:us-east-1:123456789012:listener/app/example/abc/def"
        alb_dns_name                    = "example-123.us-east-1.elb.amazonaws.com"
        listener_priority               = 200
        path_pattern                    = ["/*"]
        container_port                  = 8001
        health_check_path               = "/"
        task_cpu                        = "1024"
        task_memory                     = "2048"
        container_env_vars              = {}
        container_secret_env_vars       = {}
      })
    }
  }
}

run "sm_handoff" {
  command = plan

  variables {
    handoff_secret_name = "hybridrag-ui-app"
    image_tag           = "0.0.1"
  }

  assert {
    condition = alltrue([
      module.ecs.smoke_test_url == "http://example-123.us-east-1.elb.amazonaws.com/",
      module.ecs.image_uri == "123456789012.dkr.ecr.us-east-1.amazonaws.com/hybridrag-ui:0.0.1",
      module.ecs.container_port == 8001,
      module.ecs.task_memory == "2048",
    ])
    error_message = "UI stack should delegate to 02_app_ecs/app with SM handoff"
  }
}
