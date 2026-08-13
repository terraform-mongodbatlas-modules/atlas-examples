mock_provider "aws" {
  override_during = plan

  mock_data "aws_subnet" {
    defaults = {
      vpc_id = "vpc-mock"
    }
  }

  mock_data "aws_secretsmanager_secret" {
    defaults = {
      id  = "hybridrag-ui-app"
      arn = "arn:aws:secretsmanager:us-east-1:123456789012:secret:hybridrag-ui-app-AbCdEf"
    }
  }

  mock_data "aws_secretsmanager_secret_version" {
    defaults = {
      secret_string = jsonencode({
        aws_region                      = "us-east-1"
        name                            = "hybridrag-ui"
        private_subnet_ids              = ["subnet-aaa", "subnet-bbb"]
        ecs_security_group_id           = "sg-ecs"
        ecs_task_role_arn               = "arn:aws:iam::123456789012:role/hybridrag-ui-ecs-task"
        ecs_task_execution_role_arn     = "arn:aws:iam::123456789012:role/hybridrag-ui-ecs-exec"
        mongo_private_connection_string = "mongodb+srv://pl-0.example.mongodb.net/?authSource=%24external&authMechanism=MONGODB-AWS"
        app_database_name               = "hybridrag"
        ecr_repository_url              = "123456789012.dkr.ecr.us-east-1.amazonaws.com/hybridrag-ui"
        alb_listener_arn                = "arn:aws:elasticloadbalancing:us-east-1:123456789012:listener/app/example/abc/def"
        listener_priority               = 100
        path_pattern                    = ["/*"]
        container_port                  = 8001
        health_check_path               = "/"
        origin_header_name              = "X-Origin-Verify"
        origin_header_value             = "test-origin-header-value-32chars"
        container_env_vars              = { ENABLE_LLM = "false", CHAINLIT_DEMO_USERNAME = "demo" }
        container_secret_keys           = ["VOYAGE_API_KEY", "CHAINLIT_AUTH_SECRET", "CHAINLIT_DEMO_PASSWORD"]
        task_cpu                        = "1024"
        task_memory                     = "2048"
      })
    }
  }
}

variables {
  handoff_secret_name = "hybridrag-ui-app"
  image_tag           = "0.0.1"
}

run "ui_service_from_handoff" {
  command = plan

  assert {
    condition = alltrue([
      module.ecs_service.ecs_cluster_name == "hybridrag-ui",
      module.ecs_service.ecs_service_name == "hybridrag-ui",
      module.ecs_service.container_port == 8001,
      module.ecs_service.health_check_path == "/",
      module.ecs_service.index_run.cluster == "hybridrag-ui",
      module.ecs_service.index_run.service == "hybridrag-ui",
    ])
    error_message = "App stack should create the ECS cluster and attach the UI service (port 8001, health /)"
  }
}
