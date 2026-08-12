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
  atlas_org_id = "org123"
  cluster_name = "fastapi-minimal"
}

run "ecs_without_http_edge" {
  command = plan

  variables {
    ecr_repositories = { api = {} }
    ecs_apps = {
      api = {
        ecr_key     = "api"
        roles       = [{ database_name = "test" }]
        tfvars_path = "../02_app_ecs/infra.auto.tfvars"
      }
    }
  }

  assert {
    condition = alltrue([
      length(aws_iam_role.ecs_task) == 1,
      length(module.http_edge) == 0,
      length(module.vpc["us-east-1"].public_subnets) == 0,
    ])
    error_message = "ecs_apps without http_edges should not create ALB or public subnets"
  }
}

run "ecs_private_with_http_edge" {
  command = plan

  variables {
    ecr_repositories = { api = {}, worker = {} }
    http_edges       = { main = {} }
    ecs_apps = {
      worker = {
        ecr_key = "worker"
        roles   = [{ database_name = "jobs" }]
      }
    }
  }

  assert {
    condition = alltrue([
      length(aws_iam_role.ecs_task) == 1,
      length(module.http_edge) == 1,
      length(module.vpc["us-east-1"].public_subnets) == 2,
    ])
    error_message = "http_edges should create ALB, CloudFront, and public subnets"
  }
}

run "explicit_edge_two_apps" {
  command = plan

  variables {
    ecr_repositories = { api = {}, ui = {} }
    http_edges       = { main = {} }
    ecs_apps = {
      api = {
        ecr_key = "api"
        routing = { edge = "main", path_pattern = ["/api", "/api/*"], listener_priority = 100 }
        roles   = [{ database_name = "test" }]
      }
      ui = {
        ecr_key = "ui"
        routing = { edge = "main", path_pattern = ["/*"], listener_priority = 200 }
        roles   = [{ database_name = "test" }]
      }
    }
  }

  assert {
    condition     = length(module.http_edge) == 1
    error_message = "Two routed apps on main should share one ALB"
  }
}

run "worker_no_routing" {
  command = plan

  variables {
    ecr_repositories = { api = {}, worker = {} }
    http_edges       = { main = {} }
    ecs_apps = {
      api = {
        ecr_key = "api"
        routing = { edge = "main", path_pattern = ["/*"], listener_priority = 100 }
        roles   = [{ database_name = "test" }]
      }
      worker = {
        ecr_key = "worker"
        roles   = [{ database_name = "jobs" }]
      }
    }
  }

  assert {
    condition = alltrue([
      length(aws_iam_role.ecs_task) == 2,
      length(module.http_edge) == 1,
    ])
    error_message = "Worker without routing should not add another ALB"
  }
}

run "duplicate_listener_priority" {
  command = plan

  variables {
    ecr_repositories = { api = {}, ui = {} }
    http_edges       = { main = {} }
    ecs_apps = {
      api = {
        ecr_key = "api"
        routing = { edge = "main", path_pattern = ["/api"], listener_priority = 100 }
        roles   = [{ database_name = "test" }]
      }
      ui = {
        ecr_key = "ui"
        routing = { edge = "main", path_pattern = ["/*"], listener_priority = 100 }
        roles   = [{ database_name = "test" }]
      }
    }
  }

  expect_failures = [
    var.ecs_apps,
  ]
}

run "missing_edge_reference" {
  command = plan

  variables {
    ecr_repositories = { api = {} }
    http_edges       = { main = {} }
    ecs_apps = {
      api = {
        ecr_key = "api"
        routing = { edge = "other", path_pattern = ["/*"], listener_priority = 100 }
        roles   = [{ database_name = "test" }]
      }
    }
  }

  expect_failures = [
    var.ecs_apps,
  ]
}

run "routing_missing_match" {
  command = plan

  variables {
    ecr_repositories = { api = {} }
    http_edges       = { main = {} }
    ecs_apps = {
      api = {
        ecr_key = "api"
        routing = { edge = "main", listener_priority = 100 }
        roles   = [{ database_name = "test" }]
      }
    }
  }

  expect_failures = [
    var.ecs_apps,
  ]
}

run "aliases_without_cert" {
  command = plan

  variables {
    http_edges = {
      main = { aliases = ["api.example.com"] }
    }
  }

  expect_failures = [
    var.http_edges,
  ]
}

run "cert_without_aliases" {
  command = plan

  variables {
    http_edges = {
      main = { acm_certificate_arn = "arn:aws:acm:us-east-1:123456789012:certificate/abc" }
    }
  }

  expect_failures = [
    var.http_edges,
  ]
}

run "cert_wrong_region" {
  command = plan

  variables {
    http_edges = {
      main = {
        aliases             = ["api.example.com"]
        acm_certificate_arn = "arn:aws:acm:us-east-2:123456789012:certificate/abc"
      }
    }
  }

  expect_failures = [
    var.http_edges,
  ]
}

run "custom_domain_valid" {
  command = plan

  variables {
    ecr_repositories = { api = {} }
    http_edges = {
      main = {
        aliases             = ["api.example.com"]
        acm_certificate_arn = "arn:aws:acm:us-east-1:123456789012:certificate/abc"
      }
    }
    ecs_apps = {
      api = {
        ecr_key = "api"
        routing = { edge = "main", path_pattern = ["/*"], listener_priority = 100 }
        roles   = [{ database_name = "test" }]
      }
    }
  }

  assert {
    condition     = module.http_edge["main"].https_url == "https://api.example.com"
    error_message = "https_url should use the first alias when set"
  }
}
