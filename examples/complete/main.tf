provider "aws" {
  region = var.region
}

module "ipam" {
  source = "../.."

  operating_regions = var.operating_regions

  # The free tier is enough for this example; the provider would otherwise
  # default to the billable `advanced` tier.
  ipam_tier = "free"

  # Exercises the explicit-scope path. Pools name this scope by key, and the
  # children inherit it from their parent rather than falling back to the IPAM's
  # private default scope.
  scopes = {
    (var.scope_name) = {
      description = "Workload address space"
    }
  }

  # A full four-level hierarchy, which is the module's depth cap. Each pool names
  # its parent by key; nothing is physically nested.
  pools = {
    # Level 0 — the top of the tree, holding the whole supernet.
    core = {
      scope          = var.scope_name
      address_family = "ipv4"
      description    = "Top-level pool holding the entire private supernet"

      cidrs = {
        primary = {
          cidr = var.top_level_cidr
        }
      }
    }

    # Level 1 — regional. A locale can only be set on a pool whose parent has
    # none, and it is ForceNew.
    regional = {
      parent      = "core"
      locale      = var.region
      description = "Regional pool, carved from the supernet"

      cidrs = {
        primary = {
          netmask_length = 12
        }
      }
    }

    # Level 2 — per environment.
    env = {
      parent      = "regional"
      locale      = var.region
      description = "Environment pool"

      # Callers of this pool get a /24 unless they ask for something else.
      allocation_default_netmask_length = 24

      cidrs = {
        primary = {
          netmask_length = 16
        }
      }
    }

    # Level 3 — per application, and the deepest tier the module supports.
    app = {
      parent      = "env"
      locale      = var.region
      description = "Application pool, the deepest supported tier"

      cidrs = {
        primary = {
          netmask_length = 20
        }
      }

      # A manual reservation. This marks the space consumed inside the pool so no
      # VPC, subnet, or child pool can take it, but attaches it to nothing.
      allocations = {
        reserved = {
          netmask_length = 24
          description    = "Held for future use"
        }
      }
    }
  }

  # Cross-account monitoring is not exercised here — associating a discovery
  # needs one shared from another account — but creating the discovery itself is.
  create_resource_discovery = true

  context = module.this.context
}
