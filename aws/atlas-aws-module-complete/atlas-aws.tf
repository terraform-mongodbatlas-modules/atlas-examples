module "atlas_aws" {
  source = "github.com/terraform-mongodbatlas-modules/terraform-mongodbatlas-atlas-aws?ref=main"

  project_id = module.atlas_project.id

  # Cloud Provider Access (IAM role)
  cloud_provider_access = {
    create = true
  }

  # PrivateLink endpoints (module-managed)
  privatelink_endpoints = local.privatelink_endpoints

  # Encryption at rest (KMS)
  encryption = local.encryption_config

  # Backup export (S3)
  backup_export = local.backup_export_config

  aws_tags = var.tags

  depends_on = [module.atlas_project]
}
