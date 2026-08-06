output "subnetwork_self_link" {
  description = "Self link of the PSC subnetwork"
  value       = google_compute_subnetwork.private_endpoint.self_link
}

output "regions" {
  description = "Ready-to-consume value for the example's regions variable"
  value = [{
    name       = var.gcp_region
    subnetwork = google_compute_subnetwork.private_endpoint.self_link
  }]
}
