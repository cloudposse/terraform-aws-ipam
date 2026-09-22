# Every account already has a default resource discovery and a default
# association to its own IPAM. Neither is managed here — they are created
# implicitly with the IPAM and exported as `default_resource_discovery_id` and
# `default_resource_discovery_association_id`. What this file creates is the
# explicit discovery you need for cross-account or cross-organization
# monitoring, and the associations that bind discoveries to this IPAM.
#
# The IPAM's `operating_regions` and the discovery's are independent objects and
# the provider keeps neither in sync with the other: the IPAM's set governs which
# `locale` values pools may use, while the discovery's governs which Regions are
# discovered and monitored. This module feeds them from separate variables, and
# only falls back to the IPAM's list when the discovery's is empty.

resource "aws_vpc_ipam_resource_discovery" "default" {
  count = local.resource_discovery_enabled ? 1 : 0

  region = var.region

  description = coalesce(var.resource_discovery_description, module.this.id)

  dynamic "operating_regions" {
    for_each = toset(local.resource_discovery_operating_regions)

    content {
      region_name = operating_regions.value
    }
  }

  dynamic "organizational_unit_exclusion" {
    for_each = toset(var.resource_discovery_organizational_unit_exclusions)

    content {
      organizations_entity_path = organizational_unit_exclusion.value
    }
  }

  tags = module.this.tags
}

resource "aws_vpc_ipam_resource_discovery_association" "default" {
  for_each = local.enabled ? var.resource_discovery_associations : {}

  region = var.region

  ipam_id                    = coalesce(each.value.ipam_id, local.ipam_id)
  ipam_resource_discovery_id = each.value.ipam_resource_discovery_id

  tags = merge(module.resource_discovery_association_label[each.key].tags, each.value.tags)

  # Both IDs are Required and neither is ForceNew, and the provider's Update
  # function is a stub that makes no API calls at all — changing either would
  # plan an in-place update, do nothing, and revert on the next refresh. Force
  # the replacement the provider declines to.
  lifecycle {
    replace_triggered_by = [terraform_data.resource_discovery_association_ids[each.key]]
  }
}

# Parks the two IDs so `replace_triggered_by`, which only accepts resource
# references rather than arbitrary expressions, has something to watch.
resource "terraform_data" "resource_discovery_association_ids" {
  for_each = local.enabled ? var.resource_discovery_associations : {}

  input = {
    ipam_id                    = coalesce(each.value.ipam_id, local.ipam_id)
    ipam_resource_discovery_id = each.value.ipam_resource_discovery_id
  }
}
