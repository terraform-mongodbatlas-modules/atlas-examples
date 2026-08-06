mock_provider "google" {
  mock_data "google_compute_subnetwork" {
    defaults = {
      name      = "psc-subnet"
      project   = "host-project"
      region    = "us-east4"
      network   = "https://www.googleapis.com/compute/v1/projects/host-project/global/networks/default"
      self_link = "https://www.googleapis.com/compute/v1/projects/host-project/regions/us-east4/subnetworks/psc-subnet"
    }
    override_during = plan
  }

  mock_data "google_compute_zones" {
    defaults = {
      names = ["us-east4-c", "us-east4-a", "us-east4-b"]
    }
    override_during = plan
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
  gcp_project_id          = "test-project"
  subnetwork              = "https://www.googleapis.com/compute/v1/projects/host-project/regions/us-east4/subnetworks/psc-subnet"
  atlas_project_id        = "atlas-project"
  atlas_connection_string = "mongodb+srv://cluster0.example.mongodb.net"
}

run "automatic_zone_private_vm_and_iap_firewall" {
  command = plan

  assert {
    condition     = google_compute_instance.validation.zone == "us-east4-a"
    error_message = "The validation VM must use the first sorted available zone"
  }

  assert {
    condition     = length(google_compute_instance.validation.network_interface[0].access_config) == 0
    error_message = "The validation VM must not have a public IP"
  }

  assert {
    condition     = length(google_compute_instance.validation.service_account) == 0
    error_message = "The validation VM must not have a GCP service account"
  }

  assert {
    condition     = google_compute_instance.validation.project == "test-project"
    error_message = "The validation VM must be created in the configured service project"
  }

  assert {
    condition     = one(mongodbatlas_database_user.validation.roles).role_name == "readWrite" && one(mongodbatlas_database_user.validation.roles).database_name == "validation_test"
    error_message = "The validation database user must have least-privilege access to validation_test"
  }

  assert {
    condition     = length(google_compute_firewall.iap_ssh) == 1
    error_message = "The IAP SSH firewall rule must be enabled by default"
  }

  assert {
    condition     = google_compute_firewall.iap_ssh[0].source_ranges == toset(["35.235.240.0/20"])
    error_message = "The SSH firewall rule must allow only the IAP TCP forwarding range"
  }

  assert {
    condition     = google_compute_firewall.iap_ssh[0].target_tags == toset(["atlas-validation-vm"])
    error_message = "The IAP SSH firewall rule must target only validation VMs"
  }

  assert {
    condition     = google_compute_firewall.iap_ssh[0].project == "host-project"
    error_message = "The IAP SSH firewall rule must be created in the subnet host project"
  }

  assert {
    condition     = contains(google_compute_instance.validation.tags, "atlas-validation-vm")
    error_message = "The validation VM must carry the firewall target tag"
  }

  assert {
    condition     = length(google_compute_router.this) == 0
    error_message = "Cloud Router must be disabled by default"
  }

  assert {
    condition     = length(google_compute_router_nat.this) == 0
    error_message = "Cloud NAT must be disabled by default"
  }

  assert {
    condition     = output.validation_command == "sudo -H -u ubuntu /home/ubuntu/validate-atlas"
    error_message = "The validation command must work for metadata-based SSH and OS Login administrators"
  }
}

run "explicit_zone_and_subnet_scoped_nat" {
  command = plan

  variables {
    zone                    = "us-east4-b"
    create_iap_ssh_firewall = false
    enable_cloud_nat        = true
  }

  assert {
    condition     = google_compute_instance.validation.zone == "us-east4-b"
    error_message = "An explicit zone must override automatic zone selection"
  }

  assert {
    condition     = length(data.google_compute_zones.available) == 0
    error_message = "Available zones must not be queried when an explicit zone is provided"
  }

  assert {
    condition     = length(google_compute_firewall.iap_ssh) == 0
    error_message = "The IAP SSH firewall rule must be optional"
  }

  assert {
    condition     = length(google_compute_router.this) == 1
    error_message = "Cloud Router must be created when Cloud NAT is enabled"
  }

  assert {
    condition     = google_compute_router.this[0].project == "host-project"
    error_message = "Cloud Router must be created in the subnet host project"
  }

  assert {
    condition     = length(google_compute_router_nat.this) == 1
    error_message = "Cloud NAT must be created when enabled"
  }

  assert {
    condition     = google_compute_router_nat.this[0].source_subnetwork_ip_ranges_to_nat == "LIST_OF_SUBNETWORKS"
    error_message = "Cloud NAT must target an explicit list of subnetworks"
  }

  assert {
    condition     = length(google_compute_router_nat.this[0].subnetwork) == 1
    error_message = "Cloud NAT must target only one subnetwork"
  }

  assert {
    condition     = one(google_compute_router_nat.this[0].subnetwork).name == "https://www.googleapis.com/compute/v1/projects/host-project/regions/us-east4/subnetworks/psc-subnet"
    error_message = "Cloud NAT must target the validation VM subnetwork"
  }

  assert {
    condition     = one(google_compute_router_nat.this[0].subnetwork).source_ip_ranges_to_nat == toset(["PRIMARY_IP_RANGE"])
    error_message = "Cloud NAT must cover only the selected subnetwork primary IP range"
  }
}

run "missing_private_endpoint_connection_string_rejected" {
  command = plan

  variables {
    atlas_connection_string = null
    zone                    = "us-east4-a"
  }

  expect_failures = [google_compute_instance.validation]
}

run "srv_connection_options_are_preserved" {
  command = plan

  variables {
    atlas_connection_string = "mongodb+srv://cluster0.example.mongodb.net/?retryWrites=true&w=majority"
  }

  assert {
    condition     = nonsensitive(local.connection_string_with_creds) == "mongodb+srv://atlas-validation-user:test-password@cluster0.example.mongodb.net/?retryWrites=true&w=majority"
    error_message = "SRV connection options must be preserved when credentials are injected"
  }
}
