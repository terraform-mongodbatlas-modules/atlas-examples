# Prerequisite networking for the GCP example's E2E runs — NOT a copy of the
# example. See e2e/network-bootstrap/README.md for why this exists and how to
# keep it in sync with the example's inputs.
resource "google_compute_network" "this" {
  name                    = "atlas-examples-e2e-${var.name_suffix}"
  auto_create_subnetworks = false
}

resource "google_compute_subnetwork" "private_endpoint" {
  name          = "atlas-examples-e2e-psc-subnet-${var.name_suffix}"
  network       = google_compute_network.this.id
  region        = var.gcp_region
  ip_cidr_range = "10.0.1.0/24"
}
