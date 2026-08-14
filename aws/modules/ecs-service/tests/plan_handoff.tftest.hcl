mock_provider "aws" {
  override_during = plan

  mock_data "aws_subnet" {
    defaults = {
      vpc_id = "vpc-mock"
    }
  }
}

variables {
  image_tag = "0.0.1"
  handoff = {
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
    container_env_vars              = { ENABLE_LLM = "false" }
    container_secret_keys           = ["VOYAGE_API_KEY", "CHAINLIT_AUTH_SECRET", "CHAINLIT_DEMO_PASSWORD"]
    secret_arn                      = "arn:aws:secretsmanager:us-east-1:123456789012:secret:hybridrag-ui-app-AbCdEf"
    task_cpu                        = "1024"
    task_memory                     = "2048"
  }
}

run "creates_cluster_and_origin_header_rule" {
  command = plan

  assert {
    condition = alltrue([
      aws_ecs_cluster.this.name == "hybridrag-ui",
      aws_ecs_service.this.name == "hybridrag-ui",
      aws_lb_target_group.this.port == 8001,
      aws_lb_target_group.this.health_check[0].path == "/",
      var.handoff.origin_header_name == "X-Origin-Verify",
    ])
    error_message = "Module should create the ECS cluster from handoff.name and require the origin header"
  }
}

run "task_secrets_use_handoff_json_keys" {
  command = plan

  assert {
    condition = alltrue([
      length(jsondecode(aws_ecs_task_definition.this.container_definitions)[0].secrets) == 3,
      jsondecode(aws_ecs_task_definition.this.container_definitions)[0].secrets[0].valueFrom == "arn:aws:secretsmanager:us-east-1:123456789012:secret:hybridrag-ui-app-AbCdEf:VOYAGE_API_KEY::",
      jsondecode(aws_ecs_task_definition.this.container_definitions)[0].secrets[1].name == "CHAINLIT_AUTH_SECRET",
    ])
    error_message = "Task secrets should use handoff ARN JSON-key form, not a separate ARN map"
  }
}
