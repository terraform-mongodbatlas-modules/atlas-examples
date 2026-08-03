output "subnetwork_self_link" {
  description = "Self link of the PSC subnetwork"
  value       = google_compute_subnetwork.private_endpoint.self_link
}
