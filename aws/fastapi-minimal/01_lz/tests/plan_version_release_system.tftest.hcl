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

run "default_continuous" {
  command = plan

  assert {
    condition     = var.version_release_system == "CONTINUOUS"
    error_message = "Default version_release_system should be CONTINUOUS"
  }
}

run "lts_override" {
  command = plan

  variables {
    version_release_system = "LTS"
  }

  assert {
    condition     = var.version_release_system == "LTS"
    error_message = "version_release_system should accept LTS"
  }
}

run "invalid_value" {
  command = plan

  variables {
    version_release_system = "BETA"
  }

  expect_failures = [
    var.version_release_system,
  ]
}
