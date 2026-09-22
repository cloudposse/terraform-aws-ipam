output "delegated_admin_account_id" {
  description = "ID of the account holding the IPAM delegation"
  value       = one(aws_vpc_ipam_organization_admin_account.default[*].id)
}

output "arn" {
  description = "AWS Organizations ARN of the delegated account"
  value       = one(aws_vpc_ipam_organization_admin_account.default[*].arn)
}

output "email" {
  description = "Email address of the delegated account, read from AWS Organizations"
  value       = one(aws_vpc_ipam_organization_admin_account.default[*].email)
}

output "name" {
  description = "Name of the delegated account, read from AWS Organizations"
  value       = one(aws_vpc_ipam_organization_admin_account.default[*].name)
}

output "service_principal" {
  description = "Service principal the delegation is registered against, always `ipam.amazonaws.com`"
  value       = one(aws_vpc_ipam_organization_admin_account.default[*].service_principal)
}
