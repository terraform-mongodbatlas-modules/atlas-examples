mock_provider "mongodbatlas" {
  override_during = plan
}
mock_provider "local" {}

variables {
  project_id = "507f1f77bcf86cd799439011"
}

run "default_key_name" {
  command = plan

  assert {
    condition     = mongodbatlas_ai_model_api_key.this.name == "fastapi-minimal-voyage"
    error_message = "Default key_name should be fastapi-minimal-voyage"
  }
}

run "custom_key_name" {
  command = plan

  variables {
    key_name = "lab-voyage"
  }

  assert {
    condition     = mongodbatlas_ai_model_api_key.this.name == "lab-voyage"
    error_message = "key_name override should apply to the resource"
  }
}

run "handoff_file" {
  command = plan

  variables {
    output_path = "../secrets/voyage.auto.tfvars.json"
  }

  assert {
    condition = alltrue([
      length(local_file.voyage_handoff) == 1,
      local_file.voyage_handoff[0].filename == "../secrets/voyage.auto.tfvars.json",
    ])
    error_message = "output_path should create a voyage handoff file"
  }
}

run "no_handoff" {
  command = plan

  assert {
    condition     = length(local_file.voyage_handoff) == 0
    error_message = "Null output_path should not create a handoff file"
  }
}

run "invalid_project_id" {
  command = plan

  variables {
    project_id = "not-a-project-id"
  }

  expect_failures = [
    var.project_id,
  ]
}

run "empty_output_path" {
  command = plan

  variables {
    output_path = "   "
  }

  expect_failures = [
    var.output_path,
  ]
}
