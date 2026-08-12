mock_provider "mongodbatlas" {
  override_during = plan
}
mock_provider "aws" {
  override_during = plan
  mock_data "aws_availability_zones" {
    defaults = { names = ["us-east-1a", "us-east-1b", "us-east-1c", "us-east-1d", "us-east-1e", "us-east-1f"] }
  }
}
mock_provider "local" {}

override_module {
  target          = module.atlas_cluster
  override_during = plan
  outputs = {
    cluster_name = "fastapi-minimal"
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
  cluster_name = "fastapi-minimal"
}

run "handoff_includes_iam_query_params" {
  command = plan

  variables {
    ecr_repositories = { api = {} }
    lambda_apps = {
      api = {
        ecr_key     = "api"
        roles       = [{ database_name = "test" }]
        tfvars_path = "../02_app_lambda/infra.auto.tfvars"
      }
    }
  }

  assert {
    condition = alltrue([
      strcontains(local.mongo_iam_connection_strings_by_region["us-east-1"], "authMechanism=MONGODB-AWS"),
      strcontains(local.mongo_iam_connection_strings_by_region["us-east-1"], "authSource=%24external"),
      !strcontains(local.mongo_private_connection_string, "authMechanism"),
      local.app_handoff_payloads["api"].mongo_private_connection_string == local.mongo_iam_connection_strings_by_region["us-east-1"],
    ])
    error_message = "Handoff should append IAM query params; atlas output stays hostname-only SRV"
  }
}

run "existing_query_params_use_ampersand" {
  command = plan

  override_module {
    target          = module.atlas_cluster
    override_during = plan
    outputs = {
      cluster_name = "fastapi-minimal"
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
    ecr_repositories = { api = {} }
    lambda_apps = {
      api = {
        ecr_key = "api"
        roles   = [{ database_name = "test" }]
      }
    }
  }

  assert {
    condition     = startswith(local.mongo_iam_connection_strings_by_region["us-east-1"], "mongodb+srv://pl-0.example.mongodb.net?loadBalanced=true&")
    error_message = "Existing query params should be extended with & not /?"
  }
}
