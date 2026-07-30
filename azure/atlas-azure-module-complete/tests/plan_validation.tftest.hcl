mock_provider "mongodbatlas" {}
mock_provider "azurerm" {}
mock_provider "azuread" {}

variables {
  atlas_org_id              = "org123"
  atlas_project_name        = "test-project"
  atlas_cluster_name        = "test-cluster"
  azure_resource_group_name = "test-rg"
  azure_subscription_id     = "00000000-0000-0000-0000-000000000000"
  enable_validation_vm      = false
  regions = [
    {
      name           = "US_EAST_2"
      azure_location = "eastus2"
      subnet_id      = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/test-rg/providers/Microsoft.Network/virtualNetworks/test-vnet/subnets/atlas-pe-subnet"
    }
  ]
}

run "single_region_infers_3_nodes" {
  command = plan

  assert {
    condition     = local.cluster_regions[0].node_count == 3
    error_message = "Single region should infer 3 nodes"
  }

  assert {
    condition     = local.cluster_regions[0].name == "US_EAST_2"
    error_message = "Region name should stay in Atlas format for cluster module"
  }
}

run "single_region_privatelink" {
  command = plan

  assert {
    condition     = length(local.privatelink_endpoints) == 1
    error_message = "Should create one privatelink endpoint"
  }

  assert {
    condition     = local.privatelink_endpoints[0].region == "US_EAST_2"
    error_message = "Privatelink region should match input"
  }

  assert {
    condition     = local.privatelink_endpoints[0].subnet_id == var.regions[0].subnet_id
    error_message = "Privatelink subnet_id should match input"
  }
}

run "backup_uses_first_region_azure_location" {
  command = plan

  assert {
    condition     = local.backup_azure_location == "eastus2"
    error_message = "Backup location should use the first region's azure_location"
  }
}

run "two_regions_even_node_inference" {
  command = plan

  variables {
    regions = [
      {
        name           = "US_EAST_2"
        azure_location = "eastus2"
        subnet_id      = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/test-rg/providers/Microsoft.Network/virtualNetworks/test-vnet/subnets/atlas-pe-subnet"
      },
      {
        name      = "US_WEST_2"
        subnet_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/test-rg/providers/Microsoft.Network/virtualNetworks/test-vnet-west/subnets/atlas-pe-subnet"
      }
    ]
  }

  assert {
    condition     = local.cluster_regions[0].node_count == 2
    error_message = "First region of even count should get 2 nodes"
  }

  assert {
    condition     = local.cluster_regions[1].node_count == 1
    error_message = "Second region of even count should get 1 node"
  }
}

run "three_regions_odd_node_inference" {
  command = plan

  variables {
    regions = [
      {
        name           = "US_EAST_2"
        azure_location = "eastus2"
        subnet_id      = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/test-rg/providers/Microsoft.Network/virtualNetworks/test-vnet/subnets/atlas-pe-subnet"
      },
      {
        name      = "US_WEST_2"
        subnet_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/test-rg/providers/Microsoft.Network/virtualNetworks/test-vnet-west/subnets/atlas-pe-subnet"
      },
      {
        name      = "US_CENTRAL"
        subnet_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/test-rg/providers/Microsoft.Network/virtualNetworks/test-vnet-central/subnets/atlas-pe-subnet"
      }
    ]
  }

  assert {
    condition     = local.cluster_regions[0].node_count == 1
    error_message = "Odd region count should infer 1 node each"
  }

  assert {
    condition     = local.cluster_regions[1].node_count == 1
    error_message = "Odd region count should infer 1 node each"
  }

  assert {
    condition     = local.cluster_regions[2].node_count == 1
    error_message = "Odd region count should infer 1 node each"
  }
}

run "explicit_node_count_override" {
  command = plan

  variables {
    regions = [
      {
        name           = "US_EAST_2"
        azure_location = "eastus2"
        subnet_id      = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/test-rg/providers/Microsoft.Network/virtualNetworks/test-vnet/subnets/atlas-pe-subnet"
        node_count     = 5
      }
    ]
  }

  assert {
    condition     = local.cluster_regions[0].node_count == 5
    error_message = "Explicit node_count should override inference"
  }
}

run "empty_regions_rejected" {
  command = plan

  variables {
    regions = []
  }

  expect_failures = [var.regions]
}

run "first_region_requires_azure_location" {
  command = plan

  variables {
    regions = [
      {
        name      = "US_WEST_2"
        subnet_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/test-rg/providers/Microsoft.Network/virtualNetworks/test-vnet-west/subnets/atlas-pe-subnet"
      }
    ]
  }

  expect_failures = [var.regions]
}
