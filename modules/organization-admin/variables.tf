variable "delegated_admin_account_id" {
  type        = string
  description = <<-EOT
    Twelve-digit ID of the AWS Organizations member account to delegate IPAM
    administration to.

    ForceNew: changing it destroys the existing delegation before creating the new
    one, and the destroy revokes IPAM delegation for the entire organization in
    between
    EOT
  nullable    = false

  validation {
    condition     = can(regex("^[0-9]{12}$", var.delegated_admin_account_id))
    error_message = "The `delegated_admin_account_id` must be a twelve-digit AWS account ID."
  }
}
