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

run "handoff_includes_iam_query_params" {
  command = plan

  variables {
    ecr_repositories = { ui = {} }
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
      output.ecs_apps["ui"].mongo.connection_string == local.mongo_iam_connection_strings_by_region["us-east-1"],
      output.ecs_apps["ui"].routing == null,
    ])
    error_message = "ecs_apps.mongo should append IAM query params; atlas output stays hostname-only SRV"
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
    ecr_repositories = { ui = {} }
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
