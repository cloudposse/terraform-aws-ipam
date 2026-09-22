variable "region" {
  type        = string
  description = "AWS Region to deploy the example into"
}

variable "operating_regions" {
  type        = list(string)
  description = <<-EOT
    Regions the IPAM may discover, monitor, and allocate from. Must include
    `region`, which the provider enforces at create time
    EOT
  default     = []
  nullable    = false
}

variable "top_level_cidr" {
  type        = string
  description = "CIDR provisioned into the top-level pool, from which every child pool draws"
}

variable "scope_name" {
  type        = string
  description = "Name of the additional private scope the pool hierarchy is created in"
}
