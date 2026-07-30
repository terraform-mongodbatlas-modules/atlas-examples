locals {
  instance_name  = "atlas-validation-vm"
  admin_username = "ubuntu"
  db_username    = "atlas-validation-user"
  network_tag    = "atlas-validation-vm"

  zone = var.zone != null ? var.zone : sort(data.google_compute_zones.available[0].names)[0]

  is_srv_connection = try(startswith(var.atlas_connection_string, "mongodb+srv://"), false)

  connection_host = try(
    regex("@([^/?]+)", var.atlas_connection_string)[0],
    regex("^mongodb(?:\\+srv)?://([^@/?]+)", var.atlas_connection_string)[0],
    ""
  )

  connection_query_params = try(regex("\\?(.+)$", var.atlas_connection_string)[0], "")

  connection_string_with_creds = local.connection_host == "" ? "" : (
    local.is_srv_connection
    ? "mongodb+srv://${mongodbatlas_database_user.validation.username}:${random_password.db_user.result}@${local.connection_host}"
    : "mongodb://${mongodbatlas_database_user.validation.username}:${random_password.db_user.result}@${local.connection_host}/${local.connection_query_params != "" ? "?${local.connection_query_params}" : ""}"
  )

  shared_scripts_path = "${path.module}/../../../shared/validation-vm"
  validate_script     = file("${local.shared_scripts_path}/validate-atlas.sh")

  cloud_init = templatefile("${local.shared_scripts_path}/cloud-init.yaml.tftpl", {
    admin_username    = local.admin_username
    validate_script   = local.validate_script
    connection_string = local.connection_string_with_creds
  })
}

data "google_compute_subnetwork" "this" {
  self_link = var.subnetwork
}

data "google_compute_zones" "available" {
  count = var.zone == null ? 1 : 0

  project = var.gcp_project_id
  region  = data.google_compute_subnetwork.this.region
  status  = "UP"
}

resource "terraform_data" "connection_string" {
  input = var.atlas_connection_string

  lifecycle {
    precondition {
      condition     = can(regex("^mongodb(?:\\+srv)?://", var.atlas_connection_string))
      error_message = "A connection string associated with the selected Atlas private endpoint is required. Re-run Terraform after Atlas publishes the endpoint association."
    }
  }
}

resource "random_password" "db_user" {
  length  = 24
  special = false
}

resource "mongodbatlas_database_user" "validation" {
  project_id         = var.atlas_project_id
  username           = local.db_username
  password           = random_password.db_user.result
  auth_database_name = "admin"

  roles {
    role_name     = "readWrite"
    database_name = "validation_test"
  }

  labels {
    key   = "purpose"
    value = "validation-vm-temporary"
  }

  depends_on = [terraform_data.connection_string]
}

resource "terraform_data" "cloud_init" {
  triggers_replace = [nonsensitive(sha256(local.cloud_init))]
}

resource "google_compute_firewall" "iap_ssh" {
  count = var.create_iap_ssh_firewall ? 1 : 0

  project     = data.google_compute_subnetwork.this.project
  name        = "atlas-validation-iap-ssh"
  description = "Allow SSH from Identity-Aware Proxy to the Atlas validation VM."
  network     = data.google_compute_subnetwork.this.network
  direction   = "INGRESS"

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = ["35.235.240.0/20"]
  target_tags   = [local.network_tag]

  depends_on = [terraform_data.connection_string]
}

resource "google_compute_router" "this" {
  count = var.enable_cloud_nat ? 1 : 0

  project = data.google_compute_subnetwork.this.project
  name    = "atlas-validation-router"
  region  = data.google_compute_subnetwork.this.region
  network = data.google_compute_subnetwork.this.network

  depends_on = [terraform_data.connection_string]
}

resource "google_compute_router_nat" "this" {
  count = var.enable_cloud_nat ? 1 : 0

  project                            = data.google_compute_subnetwork.this.project
  name                               = "atlas-validation-nat"
  router                             = google_compute_router.this[0].name
  region                             = google_compute_router.this[0].region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "LIST_OF_SUBNETWORKS"

  subnetwork {
    name                    = data.google_compute_subnetwork.this.self_link
    source_ip_ranges_to_nat = ["PRIMARY_IP_RANGE"]
  }
}

resource "google_compute_instance" "validation" {
  project      = var.gcp_project_id
  name         = local.instance_name
  machine_type = var.machine_type
  zone         = local.zone

  boot_disk {
    initialize_params {
      image = "projects/ubuntu-os-cloud/global/images/family/ubuntu-2204-lts"
      size  = 10
      type  = "pd-balanced"
    }
  }

  network_interface {
    subnetwork = data.google_compute_subnetwork.this.self_link
  }

  metadata = {
    user-data = local.cloud_init
  }

  tags = [local.network_tag]

  labels = {
    managed_by = "terraform"
    purpose    = "atlas-connectivity-validation"
  }

  allow_stopping_for_update = true

  lifecycle {
    replace_triggered_by = [terraform_data.cloud_init]

    precondition {
      condition     = startswith(local.zone, "${data.google_compute_subnetwork.this.region}-")
      error_message = "The validation VM zone must belong to the selected subnet region."
    }
  }

  depends_on = [google_compute_router_nat.this]
}
