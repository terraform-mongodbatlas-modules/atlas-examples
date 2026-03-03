# For use with atlas-gcp module
output "privatelink_config" {
  description = "Configuration for atlas-gcp privatelink_endpoints variable"
  value = [
    {
      name       = google_compute_subnetwork.us_east.region
      subnetwork = google_compute_subnetwork.us_east.self_link
    },
    {
      name       = google_compute_subnetwork.us_west.region
      subnetwork = google_compute_subnetwork.us_west.self_link
    }
  ]
}
