mock_provider "mongodbatlas" {
  override_during = plan
}

mock_provider "aws" {
  override_during = plan

  mock_data "aws_availability_zones" {
    defaults = { names = ["us-east-1a", "us-east-1b", "us-east-1c", "us-east-1d", "us-east-1e", "us-east-1f"] }
  }

  mock_data "aws_caller_identity" {
    defaults = { account_id = "123456789012" }
  }
}

mock_provider "random" {
  override_during = plan

  mock_resource "random_password" {
    defaults = { result = "test-password" }
  }
}

override_module {
  target          = module.atlas_cluster
  override_during = plan
  outputs = {
    cluster_name = "hybridrag-ui"
    state_name   = "IDLE"
    connection_strings = {
      standard_srv = "mongodb+srv://cluster.example.mongodb.net"
      private_srv  = ""
      private_endpoint = [{
        srv_connection_string = "mongodb+srv://pl-0.example.mongodb.net"
        endpoints             = []
      }]
    }
  }
}

variables {
  atlas_org_id = "org123"
  cluster_name = "hybridrag-ui"
}

run "mongo_includes_iam_query_params" {
  command = plan

  variables {
    ecs_apps = {
      ui = {
        ecr_key = "ui"
        roles   = [{ database_name = "hybridrag" }]
      }
    }
  }

  assert {
    condition = alltrue([
      strcontains(local.mongo_iam_connection_strings_by_region["us-east-1"], "authMechanism=MONGODB-AWS"),
      strcontains(local.mongo_iam_connection_strings_by_region["us-east-1"], "authSource=%24external"),
      !strcontains(local.mongo_private_connection_string, "authMechanism"),
      strcontains(local.container_env["MONGODB_URI"], "authMechanism=MONGODB-AWS"),
    ])
    error_message = "The app's MONGODB_URI should append IAM query params; the diagnostic private SRV stays hostname-only"
  }
}

run "auto_scaling_floor_defaults_to_m30" {
  command = plan

  variables {
    ecs_apps = {
      ui = {
        ecr_key = "ui"
        roles   = [{ database_name = "hybridrag" }]
      }
    }
  }

  assert {
    condition     = local.cluster_auto_scaling.compute_min_instance_size == "M30" && local.cluster_auto_scaling.compute_enabled
    error_message = "Auto-scaling should be enabled with an M30 compute floor by default"
  }
}

run "auto_scaling_floor_is_configurable" {
  command = plan

  variables {
    auto_scaling_min_instance_size = "M10"
    ecs_apps = {
      ui = {
        ecr_key = "ui"
        roles   = [{ database_name = "hybridrag" }]
      }
    }
  }

  assert {
    condition     = local.cluster_auto_scaling.compute_min_instance_size == "M10"
    error_message = "auto_scaling_min_instance_size should override the default M30 floor"
  }
}

run "existing_query_params_use_ampersand" {
  command = plan

  override_module {
    target          = module.atlas_cluster
    override_during = plan
    outputs = {
      cluster_name = "hybridrag-ui"
      state_name   = "IDLE"
      connection_strings = {
        standard_srv = "mongodb+srv://cluster.example.mongodb.net"
        private_srv  = ""
        private_endpoint = [{
          srv_connection_string = "mongodb+srv://pl-0.example.mongodb.net?loadBalanced=true"
          endpoints             = []
        }]
      }
    }
  }

  variables {
    ecs_apps = {
      ui = {
        ecr_key = "ui"
        roles   = [{ database_name = "hybridrag" }]
      }
    }
  }

  assert {
    condition     = startswith(local.mongo_iam_connection_strings_by_region["us-east-1"], "mongodb+srv://pl-0.example.mongodb.net?loadBalanced=true&")
    error_message = "Existing query params should be extended with & not /?"
  }
}
