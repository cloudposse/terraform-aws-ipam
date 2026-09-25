output "ipam_id" {
  description = "ID of the IPAM created by the module"
  value       = module.ipam.ipam_id
}

output "private_default_scope_id" {
  description = "ID of the IPAM's private default scope"
  value       = module.ipam.private_default_scope_id
}

output "public_default_scope_id" {
  description = "ID of the IPAM's public default scope, which cannot be created and is only ever consumed"
  value       = module.ipam.public_default_scope_id
}

output "scope_ids" {
  description = "IDs of the additional private scopes created by the module"
  value       = module.ipam.scope_ids
}

output "pool_ids" {
  description = "Map of pool name to pool ID, flattened across all four depth tiers"
  value       = module.ipam.pool_ids
}

output "pool_names" {
  description = "Map of pool name to the null-label ID generated for that pool"
  value       = module.ipam.pool_names
}

output "pool_cidrs" {
  description = "Map of pool name to the CIDRs provisioned into that pool"
  value       = module.ipam.pool_cidrs
}

output "pool_scope_ids" {
  description = "Map of pool name to the scope each pool was created in, proving child pools inherit their parent's scope"
  value       = module.ipam.pool_scope_ids
}

output "allocation_cidrs" {
  description = "Map of allocation key to the CIDR held by each manual reservation"
  value       = module.ipam.allocation_cidrs
}

output "resource_discovery_id" {
  description = "ID of the resource discovery created by the module"
  value       = module.ipam.resource_discovery_id
}
