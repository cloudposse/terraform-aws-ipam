# Pools are materialised one resource per depth tier, because a resource cannot
# reference itself: `source_ipam_pool_id = aws_vpc_ipam_pool.this[each.value.parent].id`
# inside `aws_vpc_ipam_pool.this` is a cycle Terraform rejects. `main.tf` computes
# the depth partition; this file declares the four tiers plus the CIDRs and
# allocations that hang off them.
#
# Ordering is the reason the CIDR resources are tiered as well. Create order has
# to be pool -> its CIDRs -> child pool -> child's CIDRs, because a child pool
# draws its space from a CIDR provisioned into the parent. Destroy is the exact
# reverse, and it matters more: `DeprovisionIpamPoolCidr` fails while any
# allocation exists against that CIDR, and a child pool's provisioned CIDR *is*
# such an allocation. A single flat CIDR resource would tear parent and child
# CIDRs down in arbitrary order, and losing that race burns the 32m
# `waitIPAMPoolCIDRAllocationsReleased` timeout before failing.

locals {
  pool_ids_level_0 = { for k, v in aws_vpc_ipam_pool.level_0 : k => v.id }
  pool_ids_level_1 = { for k, v in aws_vpc_ipam_pool.level_1 : k => v.id }
  pool_ids_level_2 = { for k, v in aws_vpc_ipam_pool.level_2 : k => v.id }
  pool_ids_level_3 = { for k, v in aws_vpc_ipam_pool.level_3 : k => v.id }

  pool_ids = merge(
    local.pool_ids_level_0,
    local.pool_ids_level_1,
    local.pool_ids_level_2,
    local.pool_ids_level_3,
  )

  pool_arns = merge(
    { for k, v in aws_vpc_ipam_pool.level_0 : k => v.arn },
    { for k, v in aws_vpc_ipam_pool.level_1 : k => v.arn },
    { for k, v in aws_vpc_ipam_pool.level_2 : k => v.arn },
    { for k, v in aws_vpc_ipam_pool.level_3 : k => v.arn },
  )

  pool_states = merge(
    { for k, v in aws_vpc_ipam_pool.level_0 : k => v.state },
    { for k, v in aws_vpc_ipam_pool.level_1 : k => v.state },
    { for k, v in aws_vpc_ipam_pool.level_2 : k => v.state },
    { for k, v in aws_vpc_ipam_pool.level_3 : k => v.state },
  )

  # Per-tier CIDR sets, keyed `<pool name>/<cidr name>`.
  cidrs_level_0 = {
    for c in flatten([
      for pk, pv in local.pools_level_0 : [
        for ck, cv in pv.cidrs : {
          key                        = format("%s/%s", pk, ck)
          pool                       = pk
          cidr                       = cv.cidr
          netmask_length             = cv.netmask_length
          cidr_authorization_context = cv.cidr_authorization_context
        }
      ]
    ]) : c.key => c
  }

  cidrs_level_1 = {
    for c in flatten([
      for pk, pv in local.pools_level_1 : [
        for ck, cv in pv.cidrs : {
          key                        = format("%s/%s", pk, ck)
          pool                       = pk
          cidr                       = cv.cidr
          netmask_length             = cv.netmask_length
          cidr_authorization_context = cv.cidr_authorization_context
        }
      ]
    ]) : c.key => c
  }

  cidrs_level_2 = {
    for c in flatten([
      for pk, pv in local.pools_level_2 : [
        for ck, cv in pv.cidrs : {
          key                        = format("%s/%s", pk, ck)
          pool                       = pk
          cidr                       = cv.cidr
          netmask_length             = cv.netmask_length
          cidr_authorization_context = cv.cidr_authorization_context
        }
      ]
    ]) : c.key => c
  }

  cidrs_level_3 = {
    for c in flatten([
      for pk, pv in local.pools_level_3 : [
        for ck, cv in pv.cidrs : {
          key                        = format("%s/%s", pk, ck)
          pool                       = pk
          cidr                       = cv.cidr
          netmask_length             = cv.netmask_length
          cidr_authorization_context = cv.cidr_authorization_context
        }
      ]
    ]) : c.key => c
  }

  # Definitions and provisioned values for every CIDR, across all four tiers.
  # The definitions come from `var.pools` and so exist even when the module is
  # disabled; the resource map is empty in that case, which is why `pool_cidrs`
  # iterates the resources and looks the definition up rather than the reverse.
  cidr_definitions = merge(
    local.cidrs_level_0,
    local.cidrs_level_1,
    local.cidrs_level_2,
    local.cidrs_level_3,
  )

  cidr_values = merge(
    { for k, v in aws_vpc_ipam_pool_cidr.level_0 : k => v.cidr },
    { for k, v in aws_vpc_ipam_pool_cidr.level_1 : k => v.cidr },
    { for k, v in aws_vpc_ipam_pool_cidr.level_2 : k => v.cidr },
    { for k, v in aws_vpc_ipam_pool_cidr.level_3 : k => v.cidr },
  )

  pool_cidrs = {
    for pk in keys(var.pools) : pk => [
      for k, v in local.cidr_values : v if local.cidr_definitions[k].pool == pk
    ]
  }

  # Manual reservations across every tier, keyed `<pool name>/<allocation name>`.
  allocations = {
    for a in flatten([
      for pk, pv in var.pools : [
        for ak, av in pv.allocations : {
          key              = format("%s/%s", pk, ak)
          pool             = pk
          cidr             = av.cidr
          netmask_length   = av.netmask_length
          disallowed_cidrs = av.disallowed_cidrs
          description      = av.description
          tags             = av.tags
        }
      ]
    ]) : a.key => a
  }
}

# ------------------------------------------------------------------------------
# Level 0 — top-level pools, sitting directly in a scope
# ------------------------------------------------------------------------------

resource "aws_vpc_ipam_pool" "level_0" {
  for_each = local.enabled ? local.pools_level_0 : {}

  region = var.region

  address_family = each.value.address_family
  ipam_scope_id  = local.pools_level_0_scope_ids[each.key]
  locale         = each.value.locale
  description    = coalesce(each.value.description, module.pool_label[each.key].id)

  aws_service           = each.value.aws_service
  public_ip_source      = each.value.public_ip_source
  publicly_advertisable = each.value.publicly_advertisable

  allocation_default_netmask_length = each.value.allocation_default_netmask_length
  allocation_max_netmask_length     = each.value.allocation_max_netmask_length
  allocation_min_netmask_length     = each.value.allocation_min_netmask_length
  allocation_resource_tags          = each.value.allocation_resource_tags
  auto_import                       = each.value.auto_import

  # Delete-time only; never sent on create or update.
  cascade = each.value.cascade

  dynamic "source_resource" {
    for_each = each.value.source_resource != null ? [each.value.source_resource] : []

    content {
      resource_id     = source_resource.value.resource_id
      resource_owner  = source_resource.value.resource_owner
      resource_region = source_resource.value.resource_region
      resource_type   = source_resource.value.resource_type
    }
  }

  tags = merge(module.pool_label[each.key].tags, each.value.tags)

  timeouts {
    create = var.pool_timeouts.create
    update = var.pool_timeouts.update
    delete = var.pool_timeouts.delete
  }
}

resource "aws_vpc_ipam_pool_cidr" "level_0" {
  for_each = local.enabled ? local.cidrs_level_0 : {}

  region = var.region

  ipam_pool_id   = local.pool_ids_level_0[each.value.pool]
  cidr           = each.value.cidr
  netmask_length = each.value.netmask_length

  dynamic "cidr_authorization_context" {
    for_each = each.value.cidr_authorization_context != null ? [each.value.cidr_authorization_context] : []

    content {
      message   = cidr_authorization_context.value.message
      signature = cidr_authorization_context.value.signature
    }
  }

  timeouts {
    create = var.pool_cidr_timeouts.create
    delete = var.pool_cidr_timeouts.delete
  }
}

# ------------------------------------------------------------------------------
# Level 1
# ------------------------------------------------------------------------------

resource "aws_vpc_ipam_pool" "level_1" {
  for_each = local.enabled ? local.pools_level_1 : {}

  region = var.region

  address_family      = each.value.address_family
  source_ipam_pool_id = local.pool_ids_level_0[each.value.parent]
  locale              = each.value.locale
  description         = coalesce(each.value.description, module.pool_label[each.key].id)

  # A child pool lives in the same scope as its parent unless told otherwise.
  ipam_scope_id = (
    each.value.ipam_scope_id != null ? each.value.ipam_scope_id : (
      each.value.scope != null ? aws_vpc_ipam_scope.default[each.value.scope].id : aws_vpc_ipam_pool.level_0[each.value.parent].ipam_scope_id
    )
  )

  aws_service           = each.value.aws_service
  public_ip_source      = each.value.public_ip_source
  publicly_advertisable = each.value.publicly_advertisable

  allocation_default_netmask_length = each.value.allocation_default_netmask_length
  allocation_max_netmask_length     = each.value.allocation_max_netmask_length
  allocation_min_netmask_length     = each.value.allocation_min_netmask_length
  allocation_resource_tags          = each.value.allocation_resource_tags
  auto_import                       = each.value.auto_import

  cascade = each.value.cascade

  dynamic "source_resource" {
    for_each = each.value.source_resource != null ? [each.value.source_resource] : []

    content {
      resource_id     = source_resource.value.resource_id
      resource_owner  = source_resource.value.resource_owner
      resource_region = source_resource.value.resource_region
      resource_type   = source_resource.value.resource_type
    }
  }

  tags = merge(module.pool_label[each.key].tags, each.value.tags)

  timeouts {
    create = var.pool_timeouts.create
    update = var.pool_timeouts.update
    delete = var.pool_timeouts.delete
  }

  # A child pool draws from space provisioned into its parent, and on destroy it
  # has to be gone before that space can be deprovisioned.
  depends_on = [aws_vpc_ipam_pool_cidr.level_0]
}

resource "aws_vpc_ipam_pool_cidr" "level_1" {
  for_each = local.enabled ? local.cidrs_level_1 : {}

  region = var.region

  ipam_pool_id   = local.pool_ids_level_1[each.value.pool]
  cidr           = each.value.cidr
  netmask_length = each.value.netmask_length

  dynamic "cidr_authorization_context" {
    for_each = each.value.cidr_authorization_context != null ? [each.value.cidr_authorization_context] : []

    content {
      message   = cidr_authorization_context.value.message
      signature = cidr_authorization_context.value.signature
    }
  }

  timeouts {
    create = var.pool_cidr_timeouts.create
    delete = var.pool_cidr_timeouts.delete
  }
}

# ------------------------------------------------------------------------------
# Level 2
# ------------------------------------------------------------------------------

resource "aws_vpc_ipam_pool" "level_2" {
  for_each = local.enabled ? local.pools_level_2 : {}

  region = var.region

  address_family      = each.value.address_family
  source_ipam_pool_id = local.pool_ids_level_1[each.value.parent]
  locale              = each.value.locale
  description         = coalesce(each.value.description, module.pool_label[each.key].id)

  ipam_scope_id = (
    each.value.ipam_scope_id != null ? each.value.ipam_scope_id : (
      each.value.scope != null ? aws_vpc_ipam_scope.default[each.value.scope].id : aws_vpc_ipam_pool.level_1[each.value.parent].ipam_scope_id
    )
  )

  aws_service           = each.value.aws_service
  public_ip_source      = each.value.public_ip_source
  publicly_advertisable = each.value.publicly_advertisable

  allocation_default_netmask_length = each.value.allocation_default_netmask_length
  allocation_max_netmask_length     = each.value.allocation_max_netmask_length
  allocation_min_netmask_length     = each.value.allocation_min_netmask_length
  allocation_resource_tags          = each.value.allocation_resource_tags
  auto_import                       = each.value.auto_import

  cascade = each.value.cascade

  dynamic "source_resource" {
    for_each = each.value.source_resource != null ? [each.value.source_resource] : []

    content {
      resource_id     = source_resource.value.resource_id
      resource_owner  = source_resource.value.resource_owner
      resource_region = source_resource.value.resource_region
      resource_type   = source_resource.value.resource_type
    }
  }

  tags = merge(module.pool_label[each.key].tags, each.value.tags)

  timeouts {
    create = var.pool_timeouts.create
    update = var.pool_timeouts.update
    delete = var.pool_timeouts.delete
  }

  depends_on = [aws_vpc_ipam_pool_cidr.level_1]
}

resource "aws_vpc_ipam_pool_cidr" "level_2" {
  for_each = local.enabled ? local.cidrs_level_2 : {}

  region = var.region

  ipam_pool_id   = local.pool_ids_level_2[each.value.pool]
  cidr           = each.value.cidr
  netmask_length = each.value.netmask_length

  dynamic "cidr_authorization_context" {
    for_each = each.value.cidr_authorization_context != null ? [each.value.cidr_authorization_context] : []

    content {
      message   = cidr_authorization_context.value.message
      signature = cidr_authorization_context.value.signature
    }
  }

  timeouts {
    create = var.pool_cidr_timeouts.create
    delete = var.pool_cidr_timeouts.delete
  }
}

# ------------------------------------------------------------------------------
# Level 3 — the deepest tier. `var.pools` validation rejects anything below this.
# ------------------------------------------------------------------------------

resource "aws_vpc_ipam_pool" "level_3" {
  for_each = local.enabled ? local.pools_level_3 : {}

  region = var.region

  address_family      = each.value.address_family
  source_ipam_pool_id = local.pool_ids_level_2[each.value.parent]
  locale              = each.value.locale
  description         = coalesce(each.value.description, module.pool_label[each.key].id)

  ipam_scope_id = (
    each.value.ipam_scope_id != null ? each.value.ipam_scope_id : (
      each.value.scope != null ? aws_vpc_ipam_scope.default[each.value.scope].id : aws_vpc_ipam_pool.level_2[each.value.parent].ipam_scope_id
    )
  )

  aws_service           = each.value.aws_service
  public_ip_source      = each.value.public_ip_source
  publicly_advertisable = each.value.publicly_advertisable

  allocation_default_netmask_length = each.value.allocation_default_netmask_length
  allocation_max_netmask_length     = each.value.allocation_max_netmask_length
  allocation_min_netmask_length     = each.value.allocation_min_netmask_length
  allocation_resource_tags          = each.value.allocation_resource_tags
  auto_import                       = each.value.auto_import

  cascade = each.value.cascade

  dynamic "source_resource" {
    for_each = each.value.source_resource != null ? [each.value.source_resource] : []

    content {
      resource_id     = source_resource.value.resource_id
      resource_owner  = source_resource.value.resource_owner
      resource_region = source_resource.value.resource_region
      resource_type   = source_resource.value.resource_type
    }
  }

  tags = merge(module.pool_label[each.key].tags, each.value.tags)

  timeouts {
    create = var.pool_timeouts.create
    update = var.pool_timeouts.update
    delete = var.pool_timeouts.delete
  }

  depends_on = [aws_vpc_ipam_pool_cidr.level_2]
}

resource "aws_vpc_ipam_pool_cidr" "level_3" {
  for_each = local.enabled ? local.cidrs_level_3 : {}

  region = var.region

  ipam_pool_id   = local.pool_ids_level_3[each.value.pool]
  cidr           = each.value.cidr
  netmask_length = each.value.netmask_length

  dynamic "cidr_authorization_context" {
    for_each = each.value.cidr_authorization_context != null ? [each.value.cidr_authorization_context] : []

    content {
      message   = cidr_authorization_context.value.message
      signature = cidr_authorization_context.value.signature
    }
  }

  timeouts {
    create = var.pool_cidr_timeouts.create
    delete = var.pool_cidr_timeouts.delete
  }
}

# ------------------------------------------------------------------------------
# Manual reservations
#
# One resource across every tier. An allocation referencing only `ipam_pool_id`
# gets no dependency edge to the CIDR it consumes, so Terraform is free to
# destroy the CIDR first — at which point the provider's Delete sits in
# `waitIPAMPoolCIDRAllocationsReleased` for the full 32m and then fails. The
# explicit `depends_on` is what stops that.
# ------------------------------------------------------------------------------

resource "aws_vpc_ipam_pool_cidr_allocation" "default" {
  for_each = local.enabled ? local.allocations : {}

  region = var.region

  ipam_pool_id   = local.pool_ids[each.value.pool]
  cidr           = each.value.cidr
  netmask_length = each.value.netmask_length
  description    = each.value.description

  # Only has any effect when IPAM is choosing the block, i.e. paired with
  # `netmask_length`. With an explicit `cidr` the provider accepts it and it does
  # nothing.
  disallowed_cidrs = each.value.disallowed_cidrs

  tags = merge(module.pool_label[each.value.pool].tags, each.value.tags)

  depends_on = [
    aws_vpc_ipam_pool_cidr.level_0,
    aws_vpc_ipam_pool_cidr.level_1,
    aws_vpc_ipam_pool_cidr.level_2,
    aws_vpc_ipam_pool_cidr.level_3,
  ]
}
