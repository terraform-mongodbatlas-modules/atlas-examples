mock_provider "mongodbatlas" {}
mock_provider "aws" {}
mock_provider "local" {}

variables {
  atlas_org_id = "org123"
  cluster_name = "fastapi-minimal"
}

run "lz_only_defaults" {
  command = plan

  variables {
    manual_scaling = null
  }

  assert {
    condition     = local.aws_region == "us-east-1" && local.cluster_regions[0].name == "US_EAST_1"
    error_message = "Default us-east-1 should pass Atlas uppercase to cluster module"
  }

  assert {
    condition     = var.cluster_type == "SHARDED" && var.shard_count == 2
    error_message = "Default cluster should be SHARDED with shard_count 2"
  }

  assert {
    condition     = module.atlas_cluster.cluster_name == "fastapi-minimal"
    error_message = "Cluster name should match cluster_name"
  }

  assert {
    condition     = length(module.vpc) == 1 && length(module.vpc["us-east-1"].natgw_ids) == 0
    error_message = "Default path should create VPC with NAT disabled"
  }

  assert {
    condition     = var.manual_scaling == null && local.cluster_auto_scaling.compute_enabled && local.cluster_auto_scaling.disk_gb_enabled
    error_message = "Default should auto-scale compute and always auto-scale disk"
  }

  assert {
    condition     = length(aws_ecr_repository.this) == 0
    error_message = "Platform-only defaults should not create ECR"
  }

  assert {
    condition     = length(aws_iam_role.lambda_exec) == 0
    error_message = "Platform-only defaults should not create Lambda IAM roles"
  }

  assert {
    condition     = length(aws_security_group.lambda) == 0
    error_message = "Platform-only defaults should not create Lambda security groups"
  }

  assert {
    condition     = length(mongodbatlas_database_user.lambda) == 0
    error_message = "Platform-only defaults should not create Atlas IAM DB users"
  }

  assert {
    condition     = length(local_file.app_tfvars) == 0
    error_message = "Platform-only defaults should not write app handoff files"
  }

  assert {
    condition     = var.public_debug_access == null && length(mongodbatlas_database_user.public_debug) == 0
    error_message = "Platform-only defaults should not create public debug user"
  }

  assert {
    condition     = length(output.database.users) == 0
    error_message = "database.users should be empty with no app targets"
  }

  assert {
    condition     = output.atlas.cluster_name == "fastapi-minimal"
    error_message = "atlas.cluster_name should resolve on platform-only apply"
  }
}

run "lambda_fastapi_path" {
  command = plan

  variables {
    ecr_repositories = { api = {} }
    lambda_apps = {
      default = {
        ecr_key     = "api"
        roles       = [{ database_name = "test" }]
        tfvars_path = "../02_app_lambda/infra.auto.tfvars"
      }
    }
  }

  assert {
    condition     = length(aws_ecr_repository.this) == 1 && contains(keys(aws_ecr_repository.this), "api")
    error_message = "Lambda path should create ECR keyed api"
  }

  assert {
    condition     = length(aws_iam_role.lambda_exec) == 1 && local.lambda_apps["default"].ecr_key == "api"
    error_message = "Lambda path should create one IAM role referencing ecr_key api"
  }

  assert {
    condition     = length(aws_security_group.lambda) == 1 && local.lambda_apps["default"].aws_region == "us-east-1"
    error_message = "Lambda app should use regions[0] AWS region"
  }

  assert {
    condition = length([
      for r in mongodbatlas_database_user.lambda["default"].roles :
      r if r.role_name == "readWrite" && r.database_name == "test"
    ]) == 1 && length(mongodbatlas_database_user.lambda) == 1
    error_message = "IAM DB user should be readWrite on test only"
  }

  assert {
    condition     = length(local_file.app_tfvars) == 1 && local_file.app_tfvars["default"].filename == "../02_app_lambda/infra.auto.tfvars"
    error_message = "Handoff path should target 02_app_lambda"
  }

  assert {
    condition     = length(output.database.users) == 1 && output.database.users[0].source == "lambda_apps"
    error_message = "database.users should list one lambda_apps entry"
  }

  assert {
    condition     = contains(keys(output.ecr_repositories), "api")
    error_message = "ecr_repositories output should include api key"
  }

  assert {
    condition     = output.lambda_apps["default"].tfvars_path == "../02_app_lambda/infra.auto.tfvars"
    error_message = "lambda_apps tfvars_path should point at 02_app_lambda"
  }
}

run "lambda_apps_two_shared_ecr" {
  command = plan

  variables {
    atlas_org_id = "org123"
    ecr_repositories = {
      api = { name = "demo-api" }
    }
    lambda_apps = {
      default = {
        ecr_key     = "api"
        roles       = [{ database_name = "test" }]
        tfvars_path = "../02_app_lambda/infra.auto.tfvars"
      }
      worker = {
        ecr_key     = "api"
        tfvars_path = "../02_app_worker/infra.auto.tfvars"
        secret      = { name = "demo-worker-app" }
        roles = [
          { database_name = "jobs" },
          { database_name = "jobs_archive", role_name = "read" },
        ]
      }
    }
  }

  assert {
    condition     = length(aws_ecr_repository.this) == 1 && length(aws_iam_role.lambda_exec) == 2
    error_message = "Two lambda apps can share one ECR repository"
  }

  assert {
    condition     = length(local_file.app_tfvars) == 2 && length(aws_secretsmanager_secret.app) == 1
    error_message = "Each tfvars_path should write a file; only worker secret should be created"
  }

  assert {
    condition = length([
      for r in mongodbatlas_database_user.lambda["worker"].roles :
      r if r.database_name == "jobs_archive" && r.role_name == "read"
    ]) == 1 && length(mongodbatlas_database_user.lambda["worker"].roles) == 2
    error_message = "Worker DB user should grant multi-DB roles"
  }
}

run "manual_scaling" {
  command = plan

  variables {
    atlas_org_id   = "org123"
    manual_scaling = { instance_size = "M30" }
  }

  assert {
    condition     = local.cluster_instance_size == "M30" && !local.cluster_auto_scaling.compute_enabled && local.cluster_auto_scaling.disk_gb_enabled
    error_message = "manual_scaling should pin instance_size, disable compute auto-scale, keep disk auto-scale"
  }
}

run "manual_scaling_invalid_tier" {
  command = plan

  variables {
    atlas_org_id   = "org123"
    manual_scaling = { instance_size = "M0" }
  }

  expect_failures = [
    var.manual_scaling,
  ]
}

run "ecr_lifecycle_disabled" {
  command = plan

  variables {
    atlas_org_id = "org123"
    ecr_repositories = {
      api = {
        lifecycle_keep_count = 0
        scan_on_push         = false
      }
    }
  }

  assert {
    condition     = length(aws_ecr_lifecycle_policy.this) == 0
    error_message = "lifecycle_keep_count = 0 should skip lifecycle policy"
  }

  assert {
    condition     = aws_ecr_repository.this["api"].image_scanning_configuration[0].scan_on_push == false
    error_message = "scan_on_push should follow ecr_repositories setting"
  }
}

run "lambda_ecr_key_missing" {
  command = plan

  variables {
    atlas_org_id = "org123"
    ecr_repositories = {
      api = {}
    }
    lambda_apps = {
      default = {
        ecr_key = "missing"
        roles   = [{ database_name = "test" }]
      }
    }
  }

  expect_failures = [
    var.lambda_apps,
  ]
}

run "lambda_apps_empty_roles" {
  command = plan

  variables {
    atlas_org_id     = "org123"
    ecr_repositories = { api = {} }
    lambda_apps = {
      default = {
        ecr_key = "api"
        roles   = []
      }
    }
  }

  expect_failures = [
    var.lambda_apps,
  ]
}

run "create_app_secret" {
  command = plan

  variables {
    atlas_org_id     = "org123"
    ecr_repositories = { api = {} }
    lambda_apps = {
      default = {
        ecr_key     = "api"
        roles       = [{ database_name = "test" }]
        tfvars_path = "../02_app_lambda/infra.auto.tfvars"
        secret      = {}
      }
    }
  }

  assert {
    condition     = length(aws_secretsmanager_secret.app) == 1 && length(aws_secretsmanager_secret_version.app) == 1
    error_message = "secret = {} should plan secret and version with derived name"
  }

  assert {
    condition     = aws_secretsmanager_secret.app["default"].name == "default-app"
    error_message = "Derived secret name should be <app-name>-app"
  }
}

run "app_tfvars_disabled" {
  command = plan

  variables {
    atlas_org_id     = "org123"
    ecr_repositories = { api = {} }
    lambda_apps = {
      default = {
        ecr_key = "api"
        roles   = [{ database_name = "test" }]
      }
    }
  }

  assert {
    condition     = length(local_file.app_tfvars) == 0
    error_message = "Omitting tfvars_path should disable the handoff writer"
  }
}

run "replicaset_escape" {
  command = plan

  variables {
    atlas_org_id = "org123"
    cluster_type = "REPLICASET"
    cluster_name = "demo-app"
    regions      = [{ name = "eu-west-1", node_count = 3 }]
  }

  assert {
    condition     = var.cluster_type == "REPLICASET" && local.aws_region == "eu-west-1"
    error_message = "REPLICASET escape hatch and eu-west-1 region derivation should work"
  }

  assert {
    condition     = output.atlas.cluster_name == "demo-app"
    error_message = "Cluster name should follow cluster_name"
  }
}

run "vpc_byo" {
  command = plan

  variables {
    atlas_org_id = "org123"
    vpc_config = {
      create = false
      by_region = {
        us-east-1 = {
          vpc_id                  = "vpc-byo"
          private_subnet_ids      = ["subnet-aaa", "subnet-bbb"]
          vpc_cidr_block          = "10.1.0.0/16"
          private_route_table_ids = ["rtb-aaa"]
        }
      }
    }
  }

  assert {
    condition     = length(module.vpc) == 0
    error_message = "BYO vpc_config should not create the VPC module"
  }

  assert {
    condition     = local.vpc_id == "vpc-byo"
    error_message = "BYO path should use provided VPC id"
  }

  assert {
    condition     = toset(local.private_subnet_ids) == toset(["subnet-aaa", "subnet-bbb"])
    error_message = "BYO path should use provided private subnets"
  }
}
