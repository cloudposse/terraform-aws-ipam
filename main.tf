data "aws_region" "current" {}

# Guards the three graph properties of `var.pools` that no single entry can be
# checked for on its own: a `parent` naming no existing pool, a `parent` cycle,
# and nesting deeper than the tiers can express. They read the depth partition
# computed in `locals` below and name the offending pools.
#
# They are `precondition`s rather than variable `validation`s so they can see
# those locals. They hang off a `terraform_data` rather than off
# `aws_vpc_ipam_pool.level_0` for two reasons, both of which would otherwise
# leave the check silently inert:
#
#   - A precondition only runs when its resource has at least one instance, and
#     the pathological inputs are exactly the ones that empty a tier. A cycle
#     gives every pool a non-null parent, so `level_0` has no instances at all
#     and a precondition there would never fire.
#   - A precondition on a data source would not run until the AWS provider had
#     configured successfully, making a configuration error depend on working
#     credentials. `terraform_data` is a built-in and needs neither.
resource "terraform_data" "pool_graph_guard" {
  count = local.enabled && length(var.pools) > 0 ? 1 : 0

  input = local.pool_depths

  lifecycle {
    precondition {
      condition     = length(local.pools_orphaned) == 0
      error_message = "Every `parent` must name another key of `pools`. These pools name one that does not exist: ${join(", ", [for k in local.pools_orphaned : format("%s -> %s", k, local.parent_of[k])])}."
    }

    precondition {
      condition     = length(local.pools_in_cycle) == 0
      error_message = "The `parent` links in `pools` must form a tree. These pools are part of a cycle: ${join(", ", local.pools_in_cycle)}."
    }

    precondition {
      condition     = length(local.pools_over_depth) == 0
      error_message = "Pool nesting is capped at a depth of ${local.max_pool_depth}. These pools are nested deeper: ${join(", ", local.pools_over_depth)}."
    }
  }
}

locals {
  enabled = module.this.enabled

  ##########################################
  # Tick off the list of things to create

  ipam_enabled               = local.enabled && var.create_ipam
  resource_discovery_enabled = local.enabled && var.create_resource_discovery

  # The Region these resources land in. `var.region` overrides the provider, and
  # the provider makes it ForceNew through a CustomizeDiff interceptor.
  region = coalesce(var.region, data.aws_region.current.region)

  # Both `aws_vpc_ipam` and `aws_vpc_ipam_resource_discovery` reject an
  # `operating_regions` set that omits the current Region — on create only.
  operating_regions = length(var.operating_regions) > 0 ? var.operating_regions : [local.region]

  resource_discovery_operating_regions = coalescelist(
    var.resource_discovery_operating_regions,
    var.operating_regions,
    [local.region],
  )

  ##########################################
  # Resolve the IPAM and its default scope, whether created here or supplied

  ipam_id = local.ipam_enabled ? one(aws_vpc_ipam.default[*].id) : var.existing_ipam_id

  private_default_scope_id = local.ipam_enabled ? one(aws_vpc_ipam.default[*].private_default_scope_id) : var.existing_ipam_scope_id
  public_default_scope_id  = one(aws_vpc_ipam.default[*].public_default_scope_id)

  ##########################################
  # Walk the `parent` links, then partition the flat `pools` map by depth
  #
  # A resource cannot reference itself, so a single `aws_vpc_ipam_pool` block
  # cannot build an arbitrarily deep tree. Each pool is placed in a tier by
  # walking its `parent` links, and `pools.tf` declares one resource per tier.
  #
  # Terraform has no recursion, so the walk is unrolled: `ancestor_n` holds each
  # pool's n-th ancestor, or null once the chain terminates. Five hops is one
  # more than the depth cap, which is what lets a too-deep tree be told apart
  # from a cycle.

  max_pool_depth = 4

  parent_of = { for k, v in var.pools : k => v.parent }

  ancestor_1 = local.parent_of
  ancestor_2 = { for k, p in local.ancestor_1 : k => try(local.parent_of[p], null) }
  ancestor_3 = { for k, p in local.ancestor_2 : k => try(local.parent_of[p], null) }
  ancestor_4 = { for k, p in local.ancestor_3 : k => try(local.parent_of[p], null) }
  ancestor_5 = { for k, p in local.ancestor_4 : k => try(local.parent_of[p], null) }

  ancestors = {
    for k in keys(var.pools) : k => [
      local.ancestor_1[k],
      local.ancestor_2[k],
      local.ancestor_3[k],
      local.ancestor_4[k],
      local.ancestor_5[k],
    ]
  }

  # A pool naming a `parent` that is not a key of the map at all.
  pools_orphaned = sort([
    for k, p in local.parent_of : k
    if p != null && !contains(keys(var.pools), coalesce(p, "__unset__"))
  ])

  # A pool that reappears in its own ancestor chain. Checked before depth,
  # because a cycle never terminates and so also looks infinitely deep.
  pools_in_cycle = sort([
    for k, chain in local.ancestors : k if contains(chain, k)
  ])

  # Genuinely too deep: a fourth ancestor exists and it is not a cycle.
  pools_over_depth = sort([
    for k, chain in local.ancestors : k
    if local.ancestor_4[k] != null && !contains(chain, k)
  ])

  # Depth per pool, with anything invalid parked out of range so it falls into
  # no tier. That keeps the preconditions above as the thing that reports the
  # problem, rather than a tier resource failing on a missing map key.
  pool_depths = {
    for k in keys(var.pools) : k => (
      contains(local.pools_in_cycle, k) || contains(local.pools_over_depth, k) || contains(local.pools_orphaned, k)
      ? local.max_pool_depth
      : (
        local.ancestor_1[k] == null ? 0 : (
          local.ancestor_2[k] == null ? 1 : (
            local.ancestor_3[k] == null ? 2 : 3
          )
        )
      )
    )
  }

  # Gated on `enabled`: when the module is disabled the pool resources have no
  # instances, so `pools_level_0_scope_ids` below (and the CIDR/allocation locals
  # in pools.tf) must not index the now-empty `aws_vpc_ipam_scope.default`.
  pools_level_0 = { for k, v in var.pools : k => v if local.enabled && local.pool_depths[k] == 0 }
  pools_level_1 = { for k, v in var.pools : k => v if local.enabled && local.pool_depths[k] == 1 }
  pools_level_2 = { for k, v in var.pools : k => v if local.enabled && local.pool_depths[k] == 2 }
  pools_level_3 = { for k, v in var.pools : k => v if local.enabled && local.pool_depths[k] == 3 }

  # Scope for a top-level pool: an explicit ID wins, then a scope this module
  # created, then the IPAM's private default scope. Child pools inherit their
  # parent's scope instead — see `pools.tf`, where each tier reads
  # `ipam_scope_id` straight off the tier above it.
  pools_level_0_scope_ids = {
    for k, v in local.pools_level_0 : k => (
      v.ipam_scope_id != null ? v.ipam_scope_id : (
        v.scope != null ? aws_vpc_ipam_scope.default[v.scope].id : local.private_default_scope_id
      )
    )
  }
}

module "scope_label" {
  source  = "cloudposse/label/null"
  version = "0.25.0"

  for_each = var.scopes

  enabled    = local.enabled
  attributes = [each.key]
  context    = module.this.context
}

module "pool_label" {
  source  = "cloudposse/label/null"
  version = "0.25.0"

  for_each = var.pools

  enabled    = local.enabled
  attributes = [each.key]
  context    = module.this.context
}

module "resource_discovery_association_label" {
  source  = "cloudposse/label/null"
  version = "0.25.0"

  for_each = var.resource_discovery_associations

  enabled    = local.enabled
  attributes = [each.key]
  context    = module.this.context
}

# ------------------------------------------------------------------------------
# IPAM
#
# Creating one implicitly creates a public scope, a private scope, a default
# resource discovery, and a default resource discovery association. None of those
# four are managed here; they are exported as outputs.
# ------------------------------------------------------------------------------

resource "aws_vpc_ipam" "default" {
  count = local.ipam_enabled ? 1 : 0

  region = var.region

  description        = coalesce(var.ipam_description, module.this.id)
  tier               = var.ipam_tier
  enable_private_gua = var.private_gua_enabled
  metered_account    = var.metered_account

  # Delete-time only. The provider never sends this on create or update, so a
  # change here produces no plan diff until a destroy actually happens.
  cascade = var.ipam_cascade_enabled

  dynamic "operating_regions" {
    for_each = toset(local.operating_regions)

    content {
      region_name = operating_regions.value
    }
  }

  tags = module.this.tags

  timeouts {
    create = var.ipam_timeouts.create
    update = var.ipam_timeouts.update
    delete = var.ipam_timeouts.delete
  }
}

# ------------------------------------------------------------------------------
# Scopes
#
# Private only. `CreateIpamScope` cannot produce a public scope, and the schema
# has no scope-type argument — the single public scope is the one IPAM creates
# with itself, exported as `public_default_scope_id`.
# ------------------------------------------------------------------------------

resource "aws_vpc_ipam_scope" "default" {
  for_each = local.enabled ? var.scopes : {}

  region = var.region

  ipam_id     = local.ipam_id
  description = coalesce(each.value.description, module.scope_label[each.key].id)

  tags = merge(module.scope_label[each.key].tags, each.value.tags)

  # `ipam_id` is Required but not ForceNew, and the provider's Update path is
  # gated on `description` alone — changing `ipam_id` would otherwise plan a
  # no-op in-place update and silently revert on the next refresh. Force the
  # replacement the provider declines to.
  lifecycle {
    replace_triggered_by = [terraform_data.scope_ipam_id[each.key]]
  }
}

# Carries the `ipam_id` for each scope so a change to it can trigger replacement.
# `replace_triggered_by` only accepts resource references, not arbitrary
# expressions, so the value has to be parked in a resource to be watched.
resource "terraform_data" "scope_ipam_id" {
  for_each = local.enabled ? var.scopes : {}

  input = local.ipam_id
}
