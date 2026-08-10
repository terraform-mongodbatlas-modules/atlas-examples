mock_provider "mongodbatlas" {}
mock_provider "aws" {}
mock_provider "local" {}
mock_provider "random" {}

variables {
  atlas_org_id = "org123"
  cluster_name = "fastapi-minimal"
}

run "public_debug_enabled" {
  command = plan

  variables {
    public_debug_access = {
      ip_address    = "203.0.113.42"
      database_name = "test"
    }
  }

  assert {
    condition     = length(mongodbatlas_database_user.public_debug) == 1
    error_message = "public_debug_access should create one SCRAM user"
  }

  assert {
    condition     = mongodbatlas_database_user.public_debug[0].username == "debug"
    error_message = "Default public debug username should be debug"
  }

  assert {
    condition     = length([for u in output.database.users : u if u.source == "public_debug_access"]) == 1
    error_message = "database.users should list public debug user"
  }
}

run "public_debug_full_access" {
  command = plan

  variables {
    public_debug_access = {
      ip_address    = "203.0.113.42"
      database_name = "admin"
      role_name     = "readWriteAnyDatabase"
    }
  }

  assert {
    condition = length([
      for r in mongodbatlas_database_user.public_debug[0].roles :
      r if r.role_name == "readWriteAnyDatabase" && r.database_name == "admin"
    ]) == 1
    error_message = "readWriteAnyDatabase on admin should grant read/write on all databases"
  }
}

run "public_debug_invalid_ip" {
  command = plan

  variables {
    public_debug_access = {
      ip_address = "not-an-ip"
    }
  }

  expect_failures = [
    var.public_debug_access,
  ]
}

run "cluster_name_invalid" {
  command = plan

  variables {
    cluster_name = "1bad-name"
  }

  expect_failures = [
    var.cluster_name,
  ]
}
