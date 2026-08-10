mock_provider "mongodbatlas" {}
mock_provider "aws" {
  mock_data "aws_availability_zones" {
    defaults = { names = ["us-east-1a", "us-east-1b", "us-east-1c", "us-east-1d", "us-east-1e", "us-east-1f"] }
  }
}
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
    condition     = length([for u in output.database_users : u if u.id == "public_debug"]) == 1
    error_message = "database_users should list public debug user"
  }
}

run "public_debug_supplied_password" {
  command = plan

  variables {
    public_debug_access = {
      ip_address = "203.0.113.42"
      password   = "debug-password"
    }
  }

  assert {
    condition     = length(random_password.public_debug) == 0 && mongodbatlas_database_user.public_debug[0].password == "debug-password"
    error_message = "A supplied public debug password should not create or index the generated password."
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

run "public_debug_ipv6" {
  command = plan

  variables {
    public_debug_access = {
      ip_address = "2001:db8::1"
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
