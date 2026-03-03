variable "gcp_project_id" {
  type        = string
  default     = ""
  description = "Existing GCP project ID. If empty, a new project will be created."
}

variable "create_project" {
  type = object({
    enabled         = bool
    name            = string
    billing_account = string
    org_id          = optional(string)
    folder_id       = optional(string)
  })
  default = {
    enabled         = false
    name            = ""
    billing_account = ""
  }
  description = "Configuration for creating a new GCP project. Required if gcp_project_id is empty."

  validation {
    condition     = !var.create_project.enabled || (var.create_project.org_id != null || var.create_project.folder_id != null)
    error_message = "Either org_id or folder_id must be specified when creating a project."
  }
}
