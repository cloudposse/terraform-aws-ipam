output "ipam_id" {
  description = "ID of the IPAM — the one created here, or `existing_ipam_id` when `create_ipam` is `false`"
  value       = local.ipam_id
}

output "ipam_arn" {
  description = "ARN of the IPAM created by this module. `null` when `create_ipam` is `false`"
  value       = one(aws_vpc_ipam.default[*].arn)
}

output "private_default_scope_id" {
  description = "ID of the IPAM's private default scope, which top-level pools land in unless they name another"
  value       = local.private_default_scope_id
}

output "public_default_scope_id" {
  description = <<-EOT
    ID of the IPAM's public default scope. Read-only: additional public scopes
    cannot be created, so this is the only public scope there will ever be.
    `null` when `create_ipam` is `false`
    EOT
  value       = local.public_default_scope_id
}

output "default_resource_discovery_id" {
  description = "ID of the resource discovery IPAM creates alongside itself. Not managed by this module"
  value       = one(aws_vpc_ipam.default[*].default_resource_discovery_id)
}

output "default_resource_discovery_association_id" {
  description = "ID of the resource discovery association IPAM creates alongside itself. Not managed by this module"
  value       = one(aws_vpc_ipam.default[*].default_resource_discovery_association_id)
}

output "scope_count" {
  description = "Number of scopes on the IPAM, including the two default ones"
  value       = one(aws_vpc_ipam.default[*].scope_count)
}

output "scope_ids" {
  description = "Map from the keys of `scopes` to the ID of each created scope"
  value       = { for k, v in aws_vpc_ipam_scope.default : k => v.id }
}

output "scope_arns" {
  description = "Map from the keys of `scopes` to the ARN of each created scope"
  value       = { for k, v in aws_vpc_ipam_scope.default : k => v.arn }
}

output "pool_ids" {
  description = <<-EOT
    Map from the keys of `pools` to the ID of each created pool, flattened across
    every depth tier.

    This is the module's primary interface. The keys are the ones you supplied, so
    a downstream component can re-export this map whole and let its own consumers
    index it by name without knowing anything about the pool hierarchy
    EOT
  value       = local.pool_ids
}

output "pool_names" {
  description = <<-EOT
    Map from the keys of `pools` to the null-label ID generated for each pool —
    the value used as that pool's `Name` tag and as its default description
    EOT
  value       = { for k, v in module.pool_label : k => v.id }
}

output "pool_arns" {
  description = "Map from the keys of `pools` to the ARN of each created pool, flattened across every depth tier"
  value       = local.pool_arns
}

output "pool_states" {
  description = "Map from the keys of `pools` to the state of each created pool, flattened across every depth tier"
  value       = local.pool_states
}

output "pool_cidrs" {
  description = <<-EOT
    Map from the keys of `pools` to the list of CIDRs provisioned into that pool.

    A pool with no provisioned CIDRs maps to an empty list. Values for CIDRs
    requested by `netmask_length` are chosen by IPAM and so are only known after
    apply
    EOT
  value       = local.pool_cidrs
}

output "pool_scope_ids" {
  description = "Map from the keys of `pools` to the scope each pool was created in, flattened across every depth tier"
  value = merge(
    { for k, v in aws_vpc_ipam_pool.level_0 : k => v.ipam_scope_id },
    { for k, v in aws_vpc_ipam_pool.level_1 : k => v.ipam_scope_id },
    { for k, v in aws_vpc_ipam_pool.level_2 : k => v.ipam_scope_id },
    { for k, v in aws_vpc_ipam_pool.level_3 : k => v.ipam_scope_id },
  )
}

output "pool_cidr_ids" {
  description = "Map from `<pool name>/<cidr name>` to the Terraform ID of each provisioned pool CIDR, which is the composite `<cidr>_<pool id>`"
  value = merge(
    { for k, v in aws_vpc_ipam_pool_cidr.level_0 : k => v.id },
    { for k, v in aws_vpc_ipam_pool_cidr.level_1 : k => v.id },
    { for k, v in aws_vpc_ipam_pool_cidr.level_2 : k => v.id },
    { for k, v in aws_vpc_ipam_pool_cidr.level_3 : k => v.id },
  )
}

output "allocation_ids" {
  description = <<-EOT
    Map from `<pool name>/<allocation name>` to the AWS allocation ID of each
    manual reservation.

    This is `ipam_pool_allocation_id`, not the Terraform resource ID — the latter
    is the composite `<allocation id>_<pool id>` and is what `terraform import`
    takes
    EOT
  value       = { for k, v in aws_vpc_ipam_pool_cidr_allocation.default : k => v.ipam_pool_allocation_id }
}

output "allocation_cidrs" {
  description = "Map from `<pool name>/<allocation name>` to the CIDR reserved by each manual reservation"
  value       = { for k, v in aws_vpc_ipam_pool_cidr_allocation.default : k => v.cidr }
}

output "resource_discovery_id" {
  description = "ID of the resource discovery created by this module. `null` when `create_resource_discovery` is `false`"
  value       = one(aws_vpc_ipam_resource_discovery.default[*].id)
}

output "resource_discovery_arn" {
  description = "ARN of the resource discovery created by this module. `null` when `create_resource_discovery` is `false`"
  value       = one(aws_vpc_ipam_resource_discovery.default[*].arn)
}

output "resource_discovery_association_ids" {
  description = "Map from the keys of `resource_discovery_associations` to the ID of each association"
  value       = { for k, v in aws_vpc_ipam_resource_discovery_association.default : k => v.id }
}

output "ram_resource_share_arns" {
  description = "Map from the keys of `pools` that requested RAM sharing to the ARN of that pool's resource share"
  value       = { for k, v in aws_ram_resource_share.default : k => v.arn }
}
