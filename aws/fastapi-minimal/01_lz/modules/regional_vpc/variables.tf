variable "aws_region" {
  type = string
}

variable "name" {
  type = string
}

variable "cidr" {
  type = string
}

variable "az_count" {
  type = number

  validation {
    condition     = var.az_count <= length(data.aws_availability_zones.available.names)
    error_message = "aws_region ${var.aws_region} has fewer than ${var.az_count} available Availability Zones. Reduce az_count or select a region with enough Availability Zones."
  }
}

variable "enable_nat_gateway" {
  type    = bool
  default = false
}

variable "create_igw" {
  type    = bool
  default = false
}

variable "tags" {
  type    = map(string)
  default = {}
}
