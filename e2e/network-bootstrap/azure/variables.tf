variable "name_suffix" {
  description = "Unique suffix for resource names (e.g. the GitHub run ID)"
  type        = string
}

variable "azure_location" {
  description = "Azure location for the networking resources"
  type        = string
  default     = "eastus2"
}
