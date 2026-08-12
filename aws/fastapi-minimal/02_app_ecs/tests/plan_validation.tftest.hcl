mock_provider "aws" {}

variables {
  aws_region                      = "us-east-1"
  public_subnet_ids               = ["subnet-pub-a", "subnet-pub-b"]
  private_subnet_ids              = ["subnet-aaa", "subnet-bbb"]
  ecs_security_group_id           = "sg-ecs"
  ecs_task_role_arn               = "arn:aws:iam::123456789012:role/fastapi-minimal-ecs-task"
  ecs_task_execution_role_arn     = "arn:aws:iam::123456789012:role/fastapi-minimal-ecs-exec"
  mongo_private_connection_string = "mongodb+srv://pl-0.example.mongodb.net"
  ecr_repository_url              = "123456789012.dkr.ecr.us-east-1.amazonaws.com/fastapi-minimal"
}

run "ecs_wiring" {
  command = plan

  assert {
    condition = alltrue([
      aws_ecs_task_definition.this.container_definitions == jsonencode([{
        name      = "fastapi-minimal"
        image     = "123456789012.dkr.ecr.us-east-1.amazonaws.com/fastapi-minimal:0.0.1"
        essential = true
        portMappings = [{
          containerPort = 8000
          protocol      = "tcp"
        }]
        environment = [
          { name = "MONGO_URL", value = var.mongo_private_connection_string },
          { name = "USE_IAM_AUTH", value = "true" },
          { name = "DB_NAME", value = "test" },
        ]
        logConfiguration = {
          logDriver = "awslogs"
          options = {
            "awslogs-group"         = "/ecs/fastapi-minimal"
            "awslogs-region"        = "us-east-1"
            "awslogs-stream-prefix" = "ecs"
          }
        }
      }]),
      aws_ecs_service.this.launch_type == "FARGATE",
      aws_ecs_service.this.network_configuration[0].assign_public_ip == false,
    ])
    error_message = "ECS task and service should wire LZ handoff and private tasks"
  }

  assert {
    condition = alltrue([
      aws_lb.this.internal == false,
      aws_lb_listener.this.port == 80,
      aws_lb_target_group.this.port == 8000,
    ])
    error_message = "ALB should be internet-facing on :80 forwarding to :8000"
  }
}

run "public_subnet_ids_empty" {
  command = plan

  variables {
    public_subnet_ids = []
  }

  expect_failures = [
    var.public_subnet_ids,
  ]
}
