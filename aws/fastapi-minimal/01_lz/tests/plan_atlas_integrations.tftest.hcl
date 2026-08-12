mock_provider "mongodbatlas" {
  override_during = plan
}
mock_provider "aws" {
  override_during = plan
  mock_data "aws_availability_zones" {
    defaults = { names = ["us-east-1a", "us-east-1b", "us-east-1c", "us-east-1d", "us-east-1e", "us-east-1f"] }
  }
}
mock_provider "local" {}

# Cluster connection strings are computed; stub known PrivateLink SRV so plan-time
# check blocks in aws.tf do not fail terraform test with "known after apply".
override_module {
  target          = module.atlas_cluster
  override_during = plan
  outputs = {
    cluster_name = "fastapi-minimal"
    state_name   = "IDLE"
    connection_strings = {
      standard_srv = "mongodb+srv://cluster.example.mongodb.net"
      private_srv  = ""
      private_endpoint = [{
        srv_connection_string = "mongodb+srv://pl-0.example.mongodb.net"
        endpoints             = []
      }]
    }
  }
}

variables {
  atlas_org_id       = "org123"
  cluster_name       = "fastapi-minimal"
  regions            = [{ name = "us-east-1", node_count = 3 }]
  manual_scaling     = null
  ecr_repositories   = {}
  lambda_apps        = {}
  atlas_integrations = {}
}

run "defaults_all_enabled" {
  command = plan

  assert {
    condition = (
      local.atlas_aws_encryption.enabled &&
      local.atlas_aws_encryption.create_kms_key.enabled &&
      local.atlas_aws_encryption.create_kms_key.multi_region == true &&
      length(local.atlas_aws_encryption.create_kms_key.replica_regions) == 0 &&
      toset(local.atlas_aws_encryption.private_endpoint_regions) == toset(local.aws_regions) &&
      local.atlas_aws_log_integration.enabled &&
      local.atlas_aws_backup_export.enabled
    )
    error_message = "Omit atlas_integrations: encryption/log/backup enabled with module-managed CMK defaults (multi_region=true, inferred replica_regions=[], region=regions[0]) and KMS PE in every cluster AWS region"
  }
}

run "encryption_omitted_create_kms_key_defaults" {
  command = plan

  variables {
    # encryption object present without create_kms_key; optional defaults must still populate multi_region / replica_regions
    atlas_integrations = { encryption = {} }
  }

  assert {
    condition = (
      local.atlas_aws_encryption.enabled &&
      local.atlas_aws_encryption.create_kms_key.enabled &&
      local.atlas_aws_encryption.create_kms_key.multi_region == true &&
      length(local.atlas_aws_encryption.create_kms_key.replica_regions) == 0 &&
      local.atlas_aws_encryption.region == local.aws_region &&
      local.atlas_aws_encryption.create_kms_key.deletion_window_in_days == 7 &&
      local.atlas_aws_encryption.create_kms_key.enable_key_rotation == true
    )
    error_message = "encryption = {} without create_kms_key should use optional create_kms_key defaults without try()"
  }
}

run "multi_region_inferred_kms_replicas" {
  command = plan

  variables {
    regions = [
      { name = "us-east-1", node_count = 3 },
      { name = "us-east-2", node_count = 2 },
    ]
    atlas_integrations = { encryption = {} }
  }

  assert {
    condition = (
      local.atlas_aws_encryption.region == "us-east-1" &&
      local.atlas_aws_encryption.create_kms_key.multi_region == true &&
      local.atlas_aws_encryption.create_kms_key.replica_regions == toset(["us-east-2"])
    )
    error_message = "Multi-region cluster should infer replica_regions from cluster AWS regions except the primary"
  }
}

run "kms_primary_region_override" {
  command = plan

  variables {
    regions = [
      { name = "us-east-1", node_count = 3 },
      { name = "us-east-2", node_count = 2 },
    ]
    atlas_integrations = {
      encryption = {
        create_kms_key = { region = "us-east-2" }
      }
    }
  }

  assert {
    condition = (
      local.atlas_aws_encryption.region == "us-east-2" &&
      local.atlas_aws_encryption.create_kms_key.replica_regions == toset(["us-east-1"])
    )
    error_message = "create_kms_key.region should override the primary KMS region and re-infer replica_regions"
  }
}

run "kms_replica_regions_override" {
  command = plan

  variables {
    regions = [
      { name = "us-east-1", node_count = 3 },
      { name = "us-east-2", node_count = 2 },
      { name = "us-west-2", node_count = 2 },
    ]
    atlas_integrations = {
      encryption = {
        create_kms_key = { replica_regions = ["us-west-2"] }
      }
    }
  }

  assert {
    condition = (
      local.atlas_aws_encryption.region == "us-east-1" &&
      local.atlas_aws_encryption.create_kms_key.replica_regions == toset(["us-west-2"])
    )
    error_message = "Explicit replica_regions should override inference"
  }
}

run "encryption_disabled" {
  command = plan

  variables {
    atlas_integrations = { encryption = { enabled = false } }
  }

  assert {
    condition = (
      !local.atlas_aws_encryption.enabled &&
      local.atlas_aws_encryption.kms_key_arn == null &&
      local.atlas_aws_encryption.create_kms_key == null &&
      length(local.atlas_aws_encryption.private_endpoint_regions) == 0
    )
    error_message = "encryption.enabled = false should clear CMK inputs and KMS PE regions"
  }
}

run "skip_kms_private_endpoints" {
  command = plan

  variables {
    atlas_integrations = { encryption = { skip_private_endpoints = true } }
  }

  assert {
    condition     = local.atlas_aws_encryption.enabled && length(local.atlas_aws_encryption.private_endpoint_regions) == 0
    error_message = "skip_private_endpoints should clear private_endpoint_regions"
  }
}

run "byo_kms" {
  command = plan

  variables {
    atlas_integrations = {
      encryption = { kms_key_arn = "arn:aws:kms:us-east-1:123456789012:key/abc" }
    }
  }

  assert {
    condition = (
      local.atlas_aws_encryption.kms_key_arn == "arn:aws:kms:us-east-1:123456789012:key/abc" &&
      local.atlas_aws_encryption.create_kms_key == null
    )
    error_message = "BYO kms_key_arn should omit create_kms_key"
  }
}

run "log_audit_only" {
  command = plan

  variables {
    atlas_integrations = {
      log_integration = {
        integrations = [{ log_types = ["MONGOD_AUDIT"], prefix_path = "audit" }]
      }
    }
  }

  assert {
    condition = (
      length(local.atlas_aws_log_integration.integrations) == 1 &&
      contains(local.atlas_aws_log_integration.integrations[0].log_types, "MONGOD_AUDIT")
    )
    error_message = "Custom log integrations should pass through to the atlas-aws local"
  }
}

run "integrations_all_off" {
  command = plan

  variables {
    atlas_integrations = {
      encryption      = { enabled = false }
      log_integration = { enabled = false }
      backup_export   = { enabled = false }
    }
  }

  assert {
    condition = (
      !local.atlas_aws_encryption.enabled &&
      !local.atlas_aws_log_integration.enabled &&
      !local.atlas_aws_backup_export.enabled &&
      local.atlas_aws_log_integration.create_s3_bucket == null &&
      local.atlas_aws_backup_export.create_s3_bucket == null
    )
    error_message = "All three enabled = false should disable integrations and omit bucket configs"
  }
}

run "s3_force_destroy_false" {
  command = plan

  variables {
    atlas_integrations = { s3_force_destroy = false }
  }

  assert {
    condition = (
      local.atlas_aws_log_integration.create_s3_bucket.force_destroy == false &&
      local.atlas_aws_backup_export.create_s3_bucket.force_destroy == false
    )
    error_message = "atlas_integrations.s3_force_destroy should apply to both module-managed buckets"
  }
}
