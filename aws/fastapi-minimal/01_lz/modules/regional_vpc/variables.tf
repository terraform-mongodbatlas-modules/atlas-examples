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
