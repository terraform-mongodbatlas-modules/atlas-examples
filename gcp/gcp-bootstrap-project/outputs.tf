
# New project outputs

output "project_id" {
  description = "GCP project ID (existing or newly created)"
  value       = local.project_id
}

output "service_account_email" {
  value = google_service_account.this.email
}
