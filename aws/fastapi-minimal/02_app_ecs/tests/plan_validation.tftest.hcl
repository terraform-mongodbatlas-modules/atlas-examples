mock_provider "aws" {}

variables {
  handoff_secret_name             = null
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

run "ecs_wiring" {
  command = plan

  assert {
    condition = alltrue([
      module.app.container_port == 8000,
      module.app.listener_priority == 100,
    ])
    error_message = "App stack should create TG + listener rule only (no ALB)"
  }
}

run "private_subnet_ids_empty" {
  command = plan

  variables {
    private_subnet_ids              = []
    aws_region                      = "us-east-1"
    ecs_security_group_id           = "sg-ecs"
    ecs_task_role_arn               = "arn:aws:iam::123456789012:role/fastapi-minimal-ecs-task"
    ecs_task_execution_role_arn     = "arn:aws:iam::123456789012:role/fastapi-minimal-ecs-exec"
    mongo_private_connection_string = "mongodb+srv://pl-0.example.mongodb.net/?authSource=%24external&authMechanism=MONGODB-AWS"
    ecr_repository_url              = "123456789012.dkr.ecr.us-east-1.amazonaws.com/fastapi-minimal"
    alb_listener_arn                = "arn:aws:elasticloadbalancing:us-east-1:123456789012:listener/app/example/abc/def"
    alb_dns_name                    = "example-123.us-east-1.elb.amazonaws.com"
    listener_priority               = 100
  }

  expect_failures = [
    var.handoff_secret_name,
  ]
}
