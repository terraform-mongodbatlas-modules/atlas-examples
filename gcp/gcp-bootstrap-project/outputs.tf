output "project_id" {
  description = "GCP project ID (existing or newly created)"
  value       = local.project_id
}

output "service_account_email" {
  description = "Email of the service account created for running the complete example"
  value       = google_service_account.this.email
}
