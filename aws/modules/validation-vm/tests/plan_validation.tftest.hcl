mock_provider "aws" {
  mock_data "aws_vpc" {
    defaults = {
      cidr_block = "10.0.0.0/16"
    }
  }

  mock_data "aws_ami" {
    defaults = {
      id = "ami-12345678"
    }
  }
}

mock_provider "mongodbatlas" {}
mock_provider "random" {
  override_during = plan

  mock_resource "random_password" {
    defaults = {
      result = "test-password"
    }
  }
}

variables {
  vpc_id                  = "vpc-12345678"
  subnet_id               = "subnet-12345678"
  atlas_project_id        = "atlas-project"
  atlas_connection_string = "mongodb+srv://cluster0.example.mongodb.net/?retryWrites=true&w=majority"
}

run "srv_connection_options_are_preserved" {
  command = plan

  assert {
    condition     = nonsensitive(local.connection_string_with_creds) == "mongodb+srv://atlas-validation-user:test-password@cluster0.example.mongodb.net/?retryWrites=true&w=majority"
    error_message = "SRV connection options must be preserved when credentials are injected"
  }
}

run "standard_connection_options_and_existing_credentials_are_preserved" {
  command = plan

  variables {
    atlas_connection_string = "mongodb://old-user:old-password@host1.example.mongodb.net:27017,host2.example.mongodb.net:27017/?replicaSet=atlas-test&ssl=true"
  }

  assert {
    condition     = nonsensitive(local.connection_string_with_creds) == "mongodb://atlas-validation-user:test-password@host1.example.mongodb.net:27017,host2.example.mongodb.net:27017/?replicaSet=atlas-test&ssl=true"
    error_message = "Standard connection options must be preserved and existing credentials replaced"
  }
}
