variable "region" {
  type        = string
  description = <<-EOT
    AWS Region for every resource this module creates. Leave `null` to inherit the
    Region from the provider configuration.

    Changing this replaces every resource in the module. The provider applies
    `ForceNew` to `region` through a CustomizeDiff interceptor rather than a schema
    flag, so it does not show up as `ForceNew` in the resource documentation
    EOT
  default     = null
}

# ------------------------------------------------------------------------------
# IPAM
# ------------------------------------------------------------------------------

variable "create_ipam" {
  type        = bool
  description = <<-EOT
    Whether to create an `aws_vpc_ipam`.

    Set to `false` to build pools inside an IPAM that already exists — the usual
    shape for a second instance of this module in another Region, or for pools
    managed separately from the IPAM itself. When `false`, supply
    `existing_ipam_scope_id`, and `existing_ipam_id` as well if you need the
    IPAM-level outputs or any resource discovery association
    EOT
  default     = true
  nullable    = false
}

variable "existing_ipam_id" {
  type        = string
  description = "ID of an existing `aws_vpc_ipam` to build against. Only consulted when `create_ipam` is `false`"
  default     = null
}

variable "existing_ipam_scope_id" {
  type        = string
  description = <<-EOT
    ID of an existing IPAM scope that top-level pools default into. Only consulted
    when `create_ipam` is `false`.

    Required whenever `create_ipam` is `false` and `pools` contains a top-level
    pool that does not resolve a scope of its own. Scope IDs are attributes of the
    `aws_vpc_ipam` resource, so there is no way to look a default scope up from an
    IPAM ID alone — a caller binding to an existing IPAM has to pass one through
    EOT
  default     = null
}

variable "ipam_description" {
  type        = string
  description = "Description for the IPAM. Defaults to the null-label ID. Only used when `create_ipam` is `true`"
  default     = null
}

variable "operating_regions" {
  type        = list(string)
  description = <<-EOT
    Regions the IPAM may discover, monitor, and allocate from.

    The provider requires this to include the Region the module is applied into,
    and enforces that **at create time only** — removing the current Region later
    is not blocked by Terraform, though the API may still reject it. When empty,
    the module registers just the current Region.

    Fully mutable: the provider diffs the set and sends add/remove to `ModifyIpam`,
    so growing or shrinking this list never replaces the IPAM
    EOT
  default     = []
  nullable    = false
}

variable "ipam_tier" {
  type        = string
  description = <<-EOT
    IPAM tier. Valid values: `free`, `advanced`.

    Leaving this `null` inherits the provider's own default of `advanced`, which is
    the billable tier — set `free` explicitly if that is what you want. Mutable in
    place
    EOT
  default     = null

  validation {
    condition     = var.ipam_tier == null || contains(["free", "advanced"], coalesce(var.ipam_tier, "advanced"))
    error_message = "The `ipam_tier` must be one of `free` or `advanced`."
  }
}

variable "private_gua_enabled" {
  type        = bool
  description = <<-EOT
    Whether IPAM treats your own globally-unique IPv6 ranges (from `2000::/3`) as
    private address space. Maps to the provider's `enable_private_gua`. Mutable in
    place
    EOT
  default     = null
}

variable "metered_account" {
  type        = string
  description = <<-EOT
    Which account is metered for IPAM usage. Valid values: `ipam-owner`,
    `resource-owner`.

    Optional *and* Computed in the provider, so leaving it `null` never produces a
    diff
    EOT
  default     = null

  validation {
    condition     = var.metered_account == null || contains(["ipam-owner", "resource-owner"], coalesce(var.metered_account, "ipam-owner"))
    error_message = "The `metered_account` must be one of `ipam-owner` or `resource-owner`."
  }
}

variable "ipam_cascade_enabled" {
  type        = bool
  description = <<-EOT
    Whether to enable cascade delete on the IPAM.

    **Delete-time only.** The provider reads this solely in its Delete path, so
    toggling it produces no API call and no observable change until a destroy.

    On destroy it tears down every private scope, every pool inside them, and every
    allocation inside those — including address space that is in live use. Without
    it, destroying a non-empty IPAM fails, which is usually what you want. Leave
    `false` unless you are deliberately building a disposable environment
    EOT
  default     = false
  nullable    = false
}

variable "ipam_timeouts" {
  type = object({
    create = optional(string, null)
    update = optional(string, null)
    delete = optional(string, null)
  })
  description = "Operation timeouts for the `aws_vpc_ipam` resource. `null` entries inherit the provider defaults of 3m each"
  default     = {}
  nullable    = false
}

# ------------------------------------------------------------------------------
# Scopes
# ------------------------------------------------------------------------------

variable "scopes" {
  type = map(object({
    # key is the scope name, used for the null-label `attributes` slot, as the key
    # of the `scope_ids` output, and as the value a pool's `scope` names
    description = optional(string, null)
    tags        = optional(map(string), {})
  }))
  description = <<-EOT
    Additional **private** IPAM scopes to create, keyed by name. Keys must be known
    at `plan` time.

    Additional public scopes cannot be created — `CreateIpamScope` only ever
    produces a private scope, and there is no scope-type argument anywhere in the
    provider schema. The single public scope is the one IPAM creates alongside
    itself; consume it read-only through the `public_default_scope_id` output.

    Only `description` is mutable; it is the one field `ModifyIpamScope` accepts
    EOT
  default     = {}
  nullable    = false
}

# ------------------------------------------------------------------------------
# Pools
# ------------------------------------------------------------------------------

variable "pools" {
  type = map(object({
    # key is your own name for the pool. It is the key of the `pool_ids`,
    # `pool_arns` and `pool_cidrs` outputs, and the value another entry names in
    # its `parent`. Keys must be known at `plan` time, and are a compatibility
    # contract with your consumers: renaming one replaces the pool.

    # Name of the entry in this same map that is this pool's parent. Omit for a
    # top-level pool. Nesting is capped at a depth of 4 — see the validations.
    parent = optional(string, null)

    # --- identity. All ForceNew: changing any of these replaces the pool, and the
    # --- replacement cascades to every CIDR, allocation and child pool beneath it.
    address_family = optional(string, "ipv4")
    locale         = optional(string, null)

    # Scope selection, in precedence order: an explicit `ipam_scope_id` wins, then
    # `scope` naming a key of `var.scopes`, then the parent pool's scope for a
    # child, then the IPAM's private default scope.
    ipam_scope_id = optional(string, null)
    scope         = optional(string, null)

    # Public-scope pools only. `aws_service` accepts `ec2` or `global-services` —
    # the provider validates against the SDK enum, which carries both, even though
    # the upstream documentation lists only `ec2`.
    aws_service      = optional(string, null)
    public_ip_source = optional(string, null)

    # Cannot be validated from configuration: the provider does a live scope lookup
    # during apply and only sends this when `address_family` is `ipv6`, the scope is
    # public, and `public_ip_source` is not `amazon`. Setting it when unavailable
    # can report erroneous differences.
    publicly_advertisable = optional(bool, null)

    # VPC resource-planning pool. The block and all four fields are ForceNew, and
    # `resource_region` must equal this pool's `locale`.
    source_resource = optional(object({
      resource_id     = string
      resource_owner  = string
      resource_region = string
      resource_type   = optional(string, "vpc")
    }), null) # source_resource

    # --- mutable in place. These six are the entire payload `ModifyIpamPool` ever
    # --- receives; every other argument above replaces the pool.
    #
    # Provider defect: the Update path reads these with `d.GetOk` rather than
    # `d.HasChange`, and `GetOk` reports a zero value as unset. Resetting
    # `auto_import` to `false`, any netmask length to `0`, or `description` to `""`
    # is silently dropped — the API never receives it and the old value persists.
    # Treat them as one-way; to clear one, replace the pool.
    allocation_default_netmask_length = optional(number, null)
    allocation_max_netmask_length     = optional(number, null)
    allocation_min_netmask_length     = optional(number, null)
    allocation_resource_tags          = optional(map(string), {})
    auto_import                       = optional(bool, null)
    description                       = optional(string, null)

    # Delete-time only, exactly as `ipam_cascade_enabled`. On destroy this tears
    # down the pool's provisioned CIDRs, allocations and child pools. Note the
    # pool's own Delete does not *wait* for children the way the CIDR resource
    # waits for allocations — without cascade it simply fails on a non-empty pool.
    cascade = optional(bool, false)

    tags = optional(map(string), {})

    # --- CIDRs provisioned into this pool, keyed by an arbitrary name. Every
    # --- argument is ForceNew; the resource has no Update function at all.
    cidrs = optional(map(object({
      # `cidr` and `netmask_length` are mutually exclusive. Set neither and the pool
      # must carry `allocation_default_netmask_length` or the apply fails.
      cidr           = optional(string, null)
      netmask_length = optional(number, null)

      # BYOIP proof of ownership: the RIR/X.509-signed message and its signature,
      # needed solely when provisioning a public BYOIP range into a public-scope
      # pool. Never needed for private space, and never for
      # `public_ip_source = "amazon"`. Not persisted to state, so it cannot drift.
      cidr_authorization_context = optional(object({
        message   = optional(string, null)
        signature = optional(string, null)
      }), null) # cidr_authorization_context
    })), {})    # cidrs

    # --- manual reservations against this pool, keyed by an arbitrary name.
    # --- Everything except `tags` is ForceNew; the Update function is a stub that
    # --- calls no API.
    allocations = optional(map(object({
      cidr           = optional(string, null)
      netmask_length = optional(number, null)

      # Ranges IPAM must skip when *choosing* a block. Inert unless paired with
      # `netmask_length` — with an explicit `cidr` it does nothing, silently.
      disallowed_cidrs = optional(set(string), null)

      description = optional(string, null)
      tags        = optional(map(string), {})
    })), {}) # allocations

    # --- RAM sharing. Set `principals` to share this pool with other accounts,
    # --- organizational units, or the whole organization.
    ram_share = optional(object({
      principals                = optional(set(string), [])
      allow_external_principals = optional(bool, false)
      permission_arns           = optional(set(string), null)
      tags                      = optional(map(string), {})
    }), null) # ram_share
  }))         # pools
  description = <<-EOT
    IPAM pools to create, as a flat map keyed by your own name for each pool.
    Keys must be known at `plan` time.

    Hierarchy is expressed by naming another entry in this same map as a pool's
    `parent`, rather than by physically nesting the objects. A pool with no
    `parent` is top-level and sits directly in a scope. A flat keyed map is used
    because Terraform cannot express a recursive type — nesting would force
    `type = any` and give up schema documentation and IDE completion — and because
    the keys stay stable as pools are added and removed.

    **Nesting is capped at a depth of 4**: a top-level pool plus three generations
    beneath it. The cap is a Terraform limitation rather than an AWS one — a
    resource cannot reference itself, so an arbitrarily deep tree cannot be built
    from a single `aws_vpc_ipam_pool` block. The module partitions this map by
    computed depth and declares four tiers, `aws_vpc_ipam_pool.level_0` through
    `.level_3`. A deeper tree, a `parent` naming no existing pool, and a cycle in
    the `parent` links are each rejected at plan time by a separate check that
    names the offending pools.

    Each pool's provisioned CIDRs nest under its `cidrs`, its manual reservations
    under its `allocations`, and its RAM sharing under `ram_share`
    EOT
  default     = {}
  nullable    = false

  # The three graph checks over this map — unknown `parent`, `parent` cycle, and
  # depth cap — are `precondition`s in `main.tf` rather than `validation`s here.
  # They are properties of the whole graph, so they read the depth partition
  # already computed in `locals` instead of re-deriving the walk inline, and they
  # name the offending pools. The validations below are the per-entry checks that
  # genuinely are per-variable.

  validation {
    condition     = alltrue([for k, v in var.pools : contains(["ipv4", "ipv6"], v.address_family)])
    error_message = "The `address_family` must be one of `ipv4` or `ipv6`."
  }

  validation {
    condition = alltrue([
      for k, v in var.pools :
      v.public_ip_source == null || contains(["byoip", "amazon"], coalesce(v.public_ip_source, "byoip"))
    ])
    error_message = "The `public_ip_source` must be one of `byoip` or `amazon`."
  }

  validation {
    condition = alltrue([
      for k, v in var.pools :
      v.aws_service == null || contains(["ec2", "global-services"], coalesce(v.aws_service, "ec2"))
    ])
    error_message = "The `aws_service` must be one of `ec2` or `global-services`."
  }

  validation {
    condition = alltrue(flatten([
      for k, v in var.pools : [for ck, cv in v.cidrs : !(cv.cidr != null && cv.netmask_length != null)]
    ]))
    error_message = "A pool CIDR sets `cidr` or `netmask_length`, never both."
  }

  validation {
    condition = alltrue(flatten([
      for k, v in var.pools : [for ak, av in v.allocations : !(av.cidr != null && av.netmask_length != null)]
    ]))
    error_message = "An allocation sets `cidr` or `netmask_length`, never both."
  }

  validation {
    condition = alltrue([
      for k, v in var.pools :
      v.source_resource == null || try(v.source_resource.resource_region, null) == v.locale
    ])
    error_message = format(
      "The `source_resource.resource_region` must equal the pool's `locale`. Mismatched on: %s.",
      join(", ", [
        for k, v in var.pools : k
        if v.source_resource != null && try(v.source_resource.resource_region, null) != v.locale
      ])
    )
  }
}

variable "pool_timeouts" {
  type = object({
    create = optional(string, null)
    update = optional(string, null)
    delete = optional(string, null)
  })
  description = <<-EOT
    Operation timeouts applied to every `aws_vpc_ipam_pool`. `null` entries inherit
    the provider defaults.

    The provider's 35m create default is not padding — pool provisioning is
    genuinely slow. Do not shorten it without a reason
    EOT
  default     = {}
  nullable    = false
}

variable "pool_cidr_timeouts" {
  type = object({
    create = optional(string, null)
    delete = optional(string, null)
  })
  description = <<-EOT
    Operation timeouts applied to every `aws_vpc_ipam_pool_cidr`. `null` entries
    inherit the provider defaults of create 10m and delete 32m.

    **Do not lower the 32m delete.** That budget is the up-to-20-minute window AWS
    takes to release VPC and subnet allocations after the consuming resource is
    deleted, plus the deprovision wait. Shortening it turns a slow destroy into a
    failed one
    EOT
  default     = {}
  nullable    = false
}

# ------------------------------------------------------------------------------
# Resource discovery
# ------------------------------------------------------------------------------

variable "create_resource_discovery" {
  type        = bool
  description = <<-EOT
    Whether to create an `aws_vpc_ipam_resource_discovery`.

    Only needed for cross-account or cross-organization monitoring. Every account
    already gets a default resource discovery and a default association to its own
    IPAM; those surface as the `default_resource_discovery_id` and
    `default_resource_discovery_association_id` outputs and are not managed here
    EOT
  default     = false
  nullable    = false
}

variable "resource_discovery_description" {
  type        = string
  description = "Description for the resource discovery. Defaults to the null-label ID. Only used when `create_resource_discovery` is `true`"
  default     = null
}

variable "resource_discovery_operating_regions" {
  type        = list(string)
  description = <<-EOT
    Regions the resource discovery monitors. When empty, falls back to
    `operating_regions`, and then to the current Region.

    Independent of `operating_regions`: the provider keeps the two sets in no sync
    whatsoever. The IPAM's set governs which `locale` values pools may use; this
    one governs which Regions get discovered and monitored. A discovery can watch a
    Region the IPAM cannot allocate into, and vice versa.

    Like the IPAM's set, this must include the current Region at create time, and
    that rule is enforced on create only
    EOT
  default     = []
  nullable    = false
}

variable "resource_discovery_organizational_unit_exclusions" {
  type        = list(string)
  description = <<-EOT
    AWS Organizations entity paths to exclude from discovery — Organizations IDs
    joined by `/`. End a path with `/*` to exclude all child OUs. Subject to the
    documented IPAM quota on exclusions
    EOT
  default     = []
  nullable    = false
}

variable "resource_discovery_associations" {
  type = map(object({
    # key names the association and fills the null-label `attributes` slot
    ipam_id                    = optional(string, null)
    ipam_resource_discovery_id = string
    tags                       = optional(map(string), {})
  }))
  description = <<-EOT
    Resource discoveries to associate with this IPAM, keyed by name. Keys must be
    known at `plan` time. This is the bind step that lets an IPAM in one account see
    resources discovered in another. `ipam_id` defaults to this module's IPAM.

    Both IDs are Required but **not** ForceNew, and the provider's Update function
    makes zero API calls — changing either would otherwise plan an in-place update
    that does nothing and then reverts on the next refresh. The module forces
    replacement itself with `replace_triggered_by`, so changing an ID here replaces
    the association instead of silently doing nothing
    EOT
  default     = {}
  nullable    = false
}

# ------------------------------------------------------------------------------
# RAM sharing
# ------------------------------------------------------------------------------

variable "ram_share_permission_arns" {
  type        = list(string)
  description = <<-EOT
    Default RAM permission ARNs applied to every pool share that does not set its
    own `permission_arns`. Leave empty to let RAM apply its default managed
    permission for IPAM pools
    EOT
  default     = []
  nullable    = false
}
