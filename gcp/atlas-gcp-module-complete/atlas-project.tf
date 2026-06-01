module "atlas_project" {
  source  = "terraform-mongodbatlas-modules/project/mongodbatlas"
  version = "~> 0.2"

  org_id         = var.atlas_org_id
  name           = var.atlas_project_name
  tags           = var.tags
  ip_access_list = var.ip_access_list
}
