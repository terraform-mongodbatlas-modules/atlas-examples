module "atlas_aws" {
  source  = "terraform-mongodbatlas-modules/atlas-aws/mongodbatlas"
  version = "~> 0.1.0"

  project_id = module.atlas_project.id

  # ---------------------------------------------------------------------------
  # Cloud Provider Access (IAM Role)
  # ---------------------------------------------------------------------------
  # By default, this example lets the module create an IAM role for Atlas.
  #
  # To use an existing IAM role instead:
  #
  # Replace:
  #   cloud_provider_access = {
  #     create = true
  #   }
  #
  # With:
  #   cloud_provider_access = {
  #     create       = false
  #     iam_role_arn = "arn:aws:iam::123456789012:role/your-atlas-role"
  #   }
  #
  # NOTE:
  # - The IAM role must have a trust policy allowing Atlas to assume it.
  # - See Atlas documentation for required IAM permissions.
  # ---------------------------------------------------------------------------
  cloud_provider_access = {
    create = true
  }

  # ---------------------------------------------------------------------------
  # PrivateLink (BYO VPC Endpoints)
  # ---------------------------------------------------------------------------
  # By default, this example lets the module create AWS VPC Endpoints.
  #
  # To use existing VPC Endpoints instead:
  #
  # Replace:
  #   privatelink_endpoints = local.privatelink_endpoints
  #
  # With:
  #   privatelink_endpoints = []  # Disable module-managed endpoints
  #
  #   privatelink_byoe = [
  #     {
  #       region      = "us-east-1"
  #       endpoint_id = "vpce-0abc123def456789"
  #     }
  #   ]
  #
  # NOTE:
  # - Use module.atlas_aws.privatelink_service_info outputs
  #   to connect your VPC Endpoint to Atlas PrivateLink service.
  # - Ensure your VPC Endpoint is connected to the correct Atlas service.
  # ---------------------------------------------------------------------------
  privatelink_endpoints = local.privatelink_endpoints

  # ---------------------------------------------------------------------------
  # Backup Export (BYO S3 Bucket)
  # ---------------------------------------------------------------------------
  # By default, this example lets the module create an S3 bucket.
  #
  # To use an existing S3 bucket instead:
  #
  # Replace:
  #   backup_export = local.backup_export_config
  #
  # With:
  #   backup_export = {
  #     enabled     = true
  #     bucket_name = "your-existing-bucket-name"
  #     create_s3_bucket = {
  #       enabled = false
  #     }
  #   }
  #
  # NOTE:
  # - The S3 bucket must have the correct IAM policy allowing Atlas to write.
  # - See Atlas documentation for required bucket policy.
  # ---------------------------------------------------------------------------
  backup_export = local.backup_export_config

  aws_tags = var.tags

  depends_on = [module.atlas_project]
}
