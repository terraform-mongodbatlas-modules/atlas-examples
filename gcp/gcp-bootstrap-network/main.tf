# VPC Network (global resource)
resource "google_compute_network" "main" {
  name                    = var.network_name
  auto_create_subnetworks = false    # We'll create subnetworks manually
  routing_mode            = "GLOBAL" # Allows cross-region routing
}

# Subnetwork in US East (us-east1)
resource "google_compute_subnetwork" "us_east" {
  name          = "${var.network_name}-us-east1"
  region        = "us-east1"
  network       = google_compute_network.main.id
  ip_cidr_range = "10.0.0.0/20" # 4096 addresses

  # Enable private Google access for GCP services
  private_ip_google_access = true
}

# Subnetwork in US West (us-west1)
resource "google_compute_subnetwork" "us_west" {
  name          = "${var.network_name}-us-west1"
  region        = "us-west1"
  network       = google_compute_network.main.id
  ip_cidr_range = "10.1.0.0/20" # 4096 addresses (non-overlapping with US East)

  private_ip_google_access = true
}

# Firewall rule: Allow internal traffic between subnetworks
resource "google_compute_firewall" "allow_internal" {
  name    = "${var.network_name}-allow-internal"
  network = google_compute_network.main.id

  allow {
    protocol = "tcp"
    ports    = ["1024-65535"]
  }

  # Allow traffic from both subnetworks
  source_ranges = [
    google_compute_subnetwork.us_east.ip_cidr_range,
    google_compute_subnetwork.us_west.ip_cidr_range,
  ]
}

# Firewall rule: Allow SSH from IAP (Identity-Aware Proxy)
resource "google_compute_firewall" "allow_iap_ssh" {
  name    = "${var.network_name}-allow-iap-ssh"
  network = google_compute_network.main.id

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  # IAP's IP range
  source_ranges = ["35.235.240.0/20"]
}
