mock_provider "azurerm" {}
mock_provider "mongodbatlas" {}
mock_provider "random" {
  override_during = plan

  mock_resource "random_password" {
    defaults = {
      result = "TestPassword1"
    }
  }
}

variables {
  resource_group_name     = "test-rg"
  location                = "eastus2"
  subnet_id               = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/test-rg/providers/Microsoft.Network/virtualNetworks/test-vnet/subnets/atlas-pe-subnet"
  atlas_project_id        = "atlas-project"
  atlas_connection_string = "mongodb+srv://cluster0.example.mongodb.net/?retryWrites=true&w=majority"
}

run "srv_connection_options_are_preserved" {
  command = plan

  assert {
    condition     = nonsensitive(local.connection_string_with_creds) == "mongodb+srv://atlas-validation-user:TestPassword1@cluster0.example.mongodb.net/?retryWrites=true&w=majority"
    error_message = "SRV connection options must be preserved when credentials are injected"
  }
}

run "standard_connection_options_and_existing_credentials_are_preserved" {
  command = plan

  variables {
    atlas_connection_string = "mongodb://old-user:old-password@host1.example.mongodb.net:27017,host2.example.mongodb.net:27017/?replicaSet=atlas-test&ssl=true"
  }

  assert {
    condition     = nonsensitive(local.connection_string_with_creds) == "mongodb://atlas-validation-user:TestPassword1@host1.example.mongodb.net:27017,host2.example.mongodb.net:27017/?replicaSet=atlas-test&ssl=true"
    error_message = "Standard connection options must be preserved and existing credentials replaced"
  }
}
