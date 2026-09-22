# RAM sharing, one resource share per pool that asks for one. Sharing a pool is
# what lets another account create VPCs and subnets from it; the pool itself
# stays owned by, and managed from, this account.
#
# Shares are created in the IPAM's home Region. A pool with a `locale` in another
# Region is still shared from here — RAM shares the pool, not the locale.

locals {
  # Only pools that actually name a principal get a share.
  ram_shares = {
    for k, v in var.pools : k => v.ram_share
    if v.ram_share != null && length(try(v.ram_share.principals, [])) > 0
  }

  # Per-pool permission ARNs, falling back to the module-wide default and then to
  # `null`, which lets RAM apply its own managed permission for IPAM pools. The
  # argument is Computed, so `null` is the way to stay out of its way rather than
  # producing a perpetual diff.
  ram_permission_arns = {
    for k, v in local.ram_shares : k => (
      length(coalesce(v.permission_arns, toset([]))) > 0
      ? sort(tolist(v.permission_arns))
      : (length(var.ram_share_permission_arns) > 0 ? var.ram_share_permission_arns : null)
    )
  }

  # One entry per (pool, principal) pair, keyed `<pool name>/<principal>`.
  ram_principals = {
    for p in flatten([
      for pk, pv in local.ram_shares : [
        for principal in sort(tolist(pv.principals)) : {
          key       = format("%s/%s", pk, principal)
          pool      = pk
          principal = principal
        }
      ]
    ]) : p.key => p
  }
}

resource "aws_ram_resource_share" "default" {
  for_each = local.enabled ? local.ram_shares : {}

  region = var.region

  name                      = module.pool_label[each.key].id
  allow_external_principals = each.value.allow_external_principals

  permission_arns = local.ram_permission_arns[each.key]

  tags = merge(module.pool_label[each.key].tags, each.value.tags)
}

resource "aws_ram_resource_association" "default" {
  for_each = local.enabled ? local.ram_shares : {}

  region = var.region

  resource_arn       = local.pool_arns[each.key]
  resource_share_arn = aws_ram_resource_share.default[each.key].arn
}

resource "aws_ram_principal_association" "default" {
  for_each = local.enabled ? local.ram_principals : {}

  region = var.region

  principal          = each.value.principal
  resource_share_arn = aws_ram_resource_share.default[each.value.pool].arn
}
