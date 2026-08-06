locals {
  function_name  = var.name_prefix
  image_uri      = "${var.ecr_repository_url}:${var.image_tag}"
  log_group_name = "/aws/lambda/${local.function_name}"
}

resource "aws_cloudwatch_log_group" "lambda" {
  name              = local.log_group_name
  retention_in_days = 7
  tags              = var.tags
}

resource "aws_lambda_function" "app" {
  function_name = local.function_name
  package_type  = "Image"
  role          = var.lambda_execution_role_arn
  image_uri     = local.image_uri
  architectures = ["arm64"]
  timeout       = 30
  memory_size   = 512

  tracing_config {
    mode = "Active"
  }

  environment {
    variables = {
      MONGO_URL    = var.mongo_private_connection_string
      USE_IAM_AUTH = "true"
      DB_NAME      = var.app_database_name
    }
  }

  vpc_config {
    subnet_ids         = var.private_subnet_ids
    security_group_ids = [var.lambda_security_group_id]
  }

  depends_on = [aws_cloudwatch_log_group.lambda]

  tags = var.tags
}

resource "aws_lambda_function_url" "app" {
  function_name      = aws_lambda_function.app.function_name
  authorization_type = "NONE"

  cors {
    allow_credentials = true
    allow_origins     = ["*"]
    allow_methods     = ["*"]
    allow_headers     = ["date", "keep-alive", "content-type"]
    expose_headers    = ["keep-alive", "date"]
    max_age           = 86400
  }
}
