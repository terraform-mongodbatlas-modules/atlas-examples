# For use with atlas-gcp-module-complete example
output "privatelink_config" {
  description = "Region configurations for atlas-gcp-module-complete regions variable"
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
