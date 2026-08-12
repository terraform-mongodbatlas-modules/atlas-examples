variable "project_id" {
  description = "Atlas project ID from 01_lz (atlas.project_id output)."
  type        = string

  validation {
    condition     = can(regex("^([0-9a-f]{24})$", var.project_id))
    error_message = "project_id must be a 24-character hexadecimal Atlas project ID."
  }
}

variable "key_name" {
  description = "Name for the Atlas AI Model API key."
  type        = string
  default     = "fastapi-minimal-voyage"
}

variable "output_path" {
  description = "When set, writes a gitignored JSON handoff file with voyage_api_key and voyage_base_url."
  type        = string
  default     = null
  nullable    = true

  validation {
    condition     = var.output_path == null || trimspace(var.output_path) != ""
    error_message = "output_path must be null or a non-empty path."
  }
}
