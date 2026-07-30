output "instance_id" {
  description = "Compute Engine instance ID."
  value       = google_compute_instance.validation.id
}

output "instance_name" {
  description = "Compute Engine instance name."
  value       = google_compute_instance.validation.name
}

output "private_ip" {
  description = "Private IP address of the validation VM."
  value       = google_compute_instance.validation.network_interface[0].network_ip
}

output "zone" {
  description = "GCP zone containing the validation VM."
  value       = local.zone
}

output "admin_username" {
  description = "Username that owns the validation tooling on the VM."
  value       = local.admin_username
}

output "ssh_command" {
  description = "Command to connect to the private VM through IAP."
  value       = "gcloud compute ssh ${local.admin_username}@${google_compute_instance.validation.name} --project ${var.gcp_project_id} --zone ${local.zone} --tunnel-through-iap"
}

output "validation_command" {
  description = "Command to run after connecting to the VM, including through OS Login."
  value       = "sudo -H -u ${local.admin_username} /home/${local.admin_username}/validate-atlas"
}

output "iap_firewall_rule_name" {
  description = "IAP SSH firewall rule name when created."
  value       = var.create_iap_ssh_firewall ? google_compute_firewall.iap_ssh[0].name : null
}

output "cloud_router_name" {
  description = "Cloud Router name when Cloud NAT is enabled."
  value       = var.enable_cloud_nat ? google_compute_router.this[0].name : null
}

output "cloud_nat_name" {
  description = "Cloud NAT name when enabled."
  value       = var.enable_cloud_nat ? google_compute_router_nat.this[0].name : null
}
