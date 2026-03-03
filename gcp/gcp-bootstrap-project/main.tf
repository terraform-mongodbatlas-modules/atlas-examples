locals {
  # Use existing project or create a new one
  create_project = var.create_project.enabled
  project_id     = local.create_project ? google_project.this[0].project_id : var.gcp_project_id
}

# Optionally create a new GCP project
resource "google_project" "this" {
  count = local.create_project ? 1 : 0

  name            = var.create_project.name
  project_id      = lower(replace(var.create_project.name, " ", "-"))
  billing_account = var.create_project.billing_account
  org_id          = var.create_project.org_id
  folder_id       = var.create_project.folder_id

  # Recommended: don't delete the project on destroy, just remove from state
  # lifecycle {
  #   prevent_destroy = true
  # }
}

# Service Account with access to the project
resource "google_service_account" "this" {
  project      = local.project_id
  account_id   = "tf-modules-gcp-complete"
  display_name = "Complete example terraform-mongodbatlas-modules/atlas-examples/gcp"
}

resource "google_project_iam_member" "ci_network_admin" {
  project = local.project_id
  role    = "roles/compute.networkAdmin"
  member  = "serviceAccount:${google_service_account.this.email}"
}

resource "google_project_iam_member" "ci_compute_admin" {
  project = local.project_id
  role    = "roles/compute.admin"
  member  = "serviceAccount:${google_service_account.this.email}"
}

resource "google_project_iam_member" "ci_storage_admin" {
  project = local.project_id
  role    = "roles/storage.admin"
  member  = "serviceAccount:${google_service_account.this.email}"
}

data "google_client_openid_userinfo" "me" {}

# Allow a user to impersonate this service account
resource "google_service_account_iam_member" "user_impersonation" {
  service_account_id = google_service_account.this.name
  role               = "roles/iam.serviceAccountTokenCreator"
  member             = "user:${data.google_client_openid_userinfo.me.email}"
}

# Allow API Access
resource "google_project_service" "iam_credentials" {
  project = local.project_id
  service = "iamcredentials.googleapis.com"
}

resource "google_project_service" "compute" {
  project = local.project_id
  service = "compute.googleapis.com"
}

resource "google_project_service" "cloud_kms" {
  project = local.project_id
  service = "cloudkms.googleapis.com"
}

resource "google_project_service" "storage" {
  project = local.project_id
  service = "storage.googleapis.com"
}

resource "google_project_iam_member" "ci_kms_admin" {
  project = local.project_id
  role    = "roles/cloudkms.admin"
  member  = "serviceAccount:${google_service_account.this.email}"
}
