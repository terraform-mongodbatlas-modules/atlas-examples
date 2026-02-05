# =============================================================================
# Atlas Project & Cluster
# =============================================================================
output "project_id" {
  description = "MongoDB Atlas project ID."
  value       = module.atlas_project.id
}

output "cluster_id" {
  description = "Unique 24-hexadecimal digit string that identifies the cluster."
  value       = module.atlas_cluster.cluster_id
}

output "connection_string" {
  description = "Private endpoint SRV connection string (uses first region for sharded clusters)"
  value = coalesce(
    try(module.atlas_cluster.connection_strings.private_endpoint[0].srv_connection_string, ""),
    try(module.atlas_cluster.connection_strings.private_srv, ""),
    module.atlas_cluster.connection_strings.standard_srv
  )
}

# =============================================================================
# AWS Integrations
# =============================================================================
output "backup_export" {
  description = "Backup export configuration details"
  value       = module.atlas_aws.backup_export
}

output "encryption" {
  description = "Encryption at rest configuration details"
  value       = module.atlas_aws.encryption
}

output "privatelink" {
  description = "PrivateLink status per endpoint key"
  value       = module.atlas_aws.privatelink
}

output "privatelink_service_info" {
  description = "Atlas PrivateLink service info (for BYOE patterns)"
  value       = module.atlas_aws.privatelink_service_info
}

# =============================================================================
# Validation VM
# =============================================================================
output "validation_vm" {
  description = "Validation VM details and access commands"
  value = var.enable_validation_vm ? {
    # Instance details
    instance_id = module.validation_vm[0].instance_id
    private_ip  = module.validation_vm[0].private_ip
    username    = module.validation_vm[0].admin_username

    # Access commands
    ssh_command = module.validation_vm[0].ssh_command
    ssm_command = module.validation_vm[0].ssm_command

    # Networking resources created
    nat_gateway_id        = module.validation_vm[0].nat_gateway_id
    nat_gateway_public_ip = module.validation_vm[0].nat_gateway_public_ip
    eic_endpoint_id       = module.validation_vm[0].eic_endpoint_id

    # Quick start guide
    quick_start = <<-EOT
      ## Connect to the Validation VM

      Option 1 - EC2 Instance Connect (recommended):
        ${module.validation_vm[0].ssh_command}

      Option 2 - SSM Session Manager:
        ${module.validation_vm[0].ssm_command}

      ## Run Validation

      Once connected, run:
        ./validate-atlas

      This tests:
        1. DNS resolution (verifies private IPs)
        2. MongoDB connection via PrivateLink
        3. CRUD operations (insert, read, delete)

      ## Troubleshooting

      If mongosh is not installed (no internet during cloud-init):
        ./install-mongosh.sh

      View cloud-init logs:
        sudo cat /var/log/cloud-init-output.log
    EOT
  } : null
}

# =============================================================================
# Validation VM Networking (separate output for clarity)
# =============================================================================
output "validation_vm_networking" {
  description = "Networking resources created for the validation VM"
  value = var.enable_validation_vm ? {
    nat_gateway = var.validation_vm_create_nat_gateway ? {
      id        = module.validation_vm[0].nat_gateway_id
      public_ip = module.validation_vm[0].nat_gateway_public_ip
      note      = "NAT Gateway provides internet access for the private subnet. Costs ~$0.045/hr."
    } : null

    ec2_instance_connect_endpoint = var.validation_vm_create_ec2_instance_connect_endpoint ? {
      id   = module.validation_vm[0].eic_endpoint_id
      note = "EIC Endpoint allows SSH access to private instances without a bastion."
    } : null

    ssm_vpc_endpoints = var.validation_vm_create_ssm_vpc_endpoints ? {
      endpoints = module.validation_vm[0].ssm_vpc_endpoints
      note      = "VPC endpoints allow SSM access without internet connectivity."
    } : null
  } : null
}
