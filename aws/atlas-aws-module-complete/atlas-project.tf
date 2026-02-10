module "atlas_project" {
  source  = "terraform-mongodbatlas-modules/project/mongodbatlas"
  version = "~> 0.1.0"

  org_id         = var.org_id
  name           = var.project_name
  tags           = var.tags
  ip_access_list = var.ip_access_list
}
