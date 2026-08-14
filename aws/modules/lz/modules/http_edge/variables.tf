variable "aws_region" {
  type = string
}

variable "name" {
  type = string
}

variable "security_group_name" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "public_subnet_ids" {
  type = list(string)
}

variable "aliases" {
  type    = list(string)
  default = []
}

variable "acm_certificate_arn" {
  type    = string
  default = null
}

variable "idle_timeout" {
  description = "ALB connection idle timeout (seconds). Default 120 matches CloudFront origin_read_timeout."
  type        = number
  default     = 120
}

variable "waf" {
  type = object({
    enabled = optional(bool, true)
  })
  default = {}
}

variable "tags" {
  type    = map(string)
  default = {}
}
