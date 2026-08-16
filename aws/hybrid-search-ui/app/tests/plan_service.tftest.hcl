mock_provider "aws" {
  override_during = plan

  mock_data "aws_subnet" {
    defaults = {
      vpc_id = "vpc-mock"
    }
  }

  mock_data "aws_secretsmanager_secret" {
    defaults = {
      id  = "hybrid-search-ui-app"
      arn = "arn:aws:secretsmanager:us-east-1:123456789012:secret:hybrid-search-ui-app-AbCdEf"
    }
  }

  mock_data "aws_secretsmanager_secret_version" {
    defaults = {
      secret_string = jsonencode({
        aws_region         = "us-east-1"
        name               = "hybrid-search-ui"
        ecr_repository_url = "123456789012.dkr.ecr.us-east-1.amazonaws.com/hybrid-search-ui"
        network = {
          private_subnet_ids    = ["subnet-aaa", "subnet-bbb"]
          ecs_security_group_id = "sg-ecs"
        }
        iam = {
          task_role_arn           = "arn:aws:iam::123456789012:role/hybrid-search-ui-ecs-task"
          task_execution_role_arn = "arn:aws:iam::123456789012:role/hybrid-search-ui-ecs-exec"
        }
        routing = {
          listener_arn        = "arn:aws:elasticloadbalancing:us-east-1:123456789012:listener/app/example/abc/def"
          listener_priority   = 100
          path_pattern        = ["/*"]
          container_port      = 8001
          health_check_path   = "/"
          origin_header_name  = "X-Origin-Verify"
          origin_header_value = "test-origin-header-value-32chars"
        }
        container = {
          env = {
            ENABLE_LLM             = "false"
            SKIP_INDEX_CREATION    = "true"
            CHAINLIT_DEMO_USERNAME = "demo"
            MONGODB_URI            = "mongodb+srv://pl-0.example.mongodb.net/?authSource=%24external&authMechanism=MONGODB-AWS"
            MONGODB_DATABASE       = "hybrid_search"
            VOYAGE_BASE_URL        = "https://ai.mongodb.com/v1"
          }
          secret_keys = ["VOYAGE_API_KEY", "CHAINLIT_AUTH_SECRET", "CHAINLIT_DEMO_PASSWORD"]
        }
      })
    }
  }
}

variables {
  app_secret_name = "hybrid-search-ui-app"
  image_tag       = "0.0.1"
}

run "ui_service_from_app_secret" {
  command = plan

  assert {
    condition = alltrue([
      module.ecs_service.ecs_cluster_name == "hybrid-search-ui",
      module.ecs_service.ecs_service_name == "hybrid-search-ui",
      module.ecs_service.container_port == 8001,
      module.ecs_service.health_check_path == "/",
      module.ecs_service.index_run.cluster == "hybrid-search-ui",
      module.ecs_service.index_run.service == "hybrid-search-ui",
    ])
    error_message = "App stack should create the ECS cluster and attach the UI service (port 8001, health /)"
  }
}
