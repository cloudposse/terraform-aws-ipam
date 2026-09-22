# Migration From `aws-ia/ipam/aws` to `cloudposse/ipam/aws`

Users new to this module can skip this document and proceed to the main README.
This document is for users moving an existing IPAM off
[`aws-ia/terraform-aws-ipam`](https://github.com/aws-ia/terraform-aws-ipam).

There is no "tl;dr". Both modules manage the same AWS resources, so nothing has
to be recreated — but the resource **addresses** differ, and nothing this module
ships can move your state for you. That work happens in your root configuration.

This guide has four parts:

1. [Key changes](#key-changes) — what differs, and what does not
2. [Configuration migration](#configuration-migration) — before and after, and the input mapping
3. [State migration](#state-migration) — the `moved` blocks you write, and the `state mv` / `import` fallbacks
4. [Usage notes](#usage-notes) — behaviour worth knowing once you are on this module

## Key changes

Minimum version changes:

- Terraform: `>= 1.0` → `>= 1.4.0`
- AWS Provider: `>= 4.30` → `>= 6.56.0`

> [!IMPORTANT]
> The provider floor is deliberate, not incidental. 6.56.0 fixes `aws_subnet`
> failing to wait for IPAM to release its CIDR on delete. If you run
> IPAM-backed subnets, that fix removes a class of destroy-timeout failure that
> no module can work around from the inside.

#### What stays the same

- The AWS resources themselves. Every pool, provisioned CIDR, and allocation you
  have today is managed by the identical `aws_vpc_ipam*` resource type after the
  move. **No address space is recreated, released, or renumbered** if you do the
  state migration correctly.
- The pool hierarchy's shape and depth reach. aws-ia supports a top-level pool
  plus three sub-levels; so does this module. No existing hierarchy can be too
  deep.

#### What changes

- **The input is flat, not nested.** `pool_configurations` nested `sub_pools`
  inside `sub_pools`; `pools` is a single flat map where each entry names its
  `parent`.
- **The input is concretely typed.** aws-ia types `pool_configurations` as
  `type = any` with a prose schema in a comment. Every attribute here is declared,
  so terraform-docs, `terraform validate`, and editor completion all work — and
  a typo in an attribute name is an error rather than a silent no-op.
- **Resource addresses are shallow.** aws-ia materialises each depth as a call to
  a shared `./modules/sub_pool` child module, giving addresses like
  `module.level_one["core"].aws_vpc_ipam_pool.sub[0]`. This module uses four
  resources in the root: `aws_vpc_ipam_pool.level_0` … `.level_3`, indexed by your
  pool name.
- **Null-label naming and tagging.** Names, descriptions, and tags come from
  `context`, as in every Cloud Posse module.
- **RAM sharing is per-pool.** aws-ia shares via a `ram_share_principals` list
  inside each pool configuration; here it is a `ram_share` object per pool, and
  each shared pool gets its own resource share.
- **Validation is explicit.** Depth overruns, unknown `parent` references, and
  `parent` cycles fail at plan time naming the offending pools, rather than
  surfacing as a confusing cycle error or a silently-dropped pool.

## Configuration migration

### Before — `aws-ia/ipam/aws`

```hcl
module "ipam" {
  source  = "aws-ia/ipam/aws"
  version = "2.1.0"

  top_cidr       = ["10.0.0.0/8"]
  top_name       = "core"
  address_family = "ipv4"

  pool_configurations = {
    use2 = {
      name           = "us-east-2"
      description    = "Regional pool"
      locale         = "us-east-2"
      cidr           = ["10.0.0.0/12"]

      sub_pools = {
        prod = {
          name                              = "prod"
          cidr                              = ["10.0.0.0/16"]
          ram_share_principals              = [local.org_arn]
          allocation_default_netmask_length = 24
        }
      }
    }
  }
}
```

### After — `cloudposse/ipam/aws`

```hcl
module "ipam" {
  source  = "cloudposse/ipam/aws"
  version = "x.x.x"

  operating_regions = ["us-east-2"]

  pools = {
    core = {
      address_family = "ipv4"
      cidrs = {
        primary = { cidr = "10.0.0.0/8" }
      }
    }

    use2 = {
      parent      = "core"
      description = "Regional pool"
      locale      = "us-east-2"
      cidrs = {
        primary = { cidr = "10.0.0.0/12" }
      }
    }

    prod = {
      parent                            = "use2"
      locale                            = "us-east-2"
      allocation_default_netmask_length = 24
      cidrs = {
        primary = { cidr = "10.0.0.0/16" }
      }
      ram_share = {
        principals = [local.org_arn]
      }
    }
  }

  context = module.this.context
}
```

### Input mapping

| `aws-ia/ipam` | `cloudposse/ipam` | Notes |
|---|---|---|
| `top_cidr` (list) | a top-level entry in `pools` with `cidrs` | The top pool stops being special-cased; it is an ordinary entry with no `parent` |
| `top_name` | the map key of that entry | The key is the name. It also keys the `pool_ids` output |
| `address_family` (module-wide) | `pools.<key>.address_family` | Per pool, defaulting to `ipv4` |
| `pool_configurations` | `pools` | Flat, with `parent` instead of nesting |
| `pool_configurations.<k>.sub_pools.<k2>` | a `pools` entry with `parent = "<k>"` | Nesting becomes a reference. Pick your own key; it need not encode the path |
| `.name` | the map key | Redundant once the key carries meaning |
| `.description` | `.description` | Defaults to the null-label ID when omitted |
| `.cidr` (list) | `.cidrs` (map of object) | Each becomes a named entry: `cidrs = { primary = { cidr = "..." } }`. The names are yours and are used only to key state |
| `.netmask_length` | `.cidrs.<name>.netmask_length` | Mutually exclusive with `cidr`, enforced at plan time |
| `.locale` | `.locale` | Unchanged. Still ForceNew |
| `.ram_share_principals` | `.ram_share.principals` | Each shared pool gets its own resource share |
| `.allocation_default_netmask_length` | same | Unchanged |
| `.allocation_min_netmask_length` | same | Unchanged |
| `.allocation_max_netmask_length` | same | Unchanged |
| `.auto_import` | same | Unchanged |
| `.tags` | `.tags` | Merged over the null-label tags |
| `.aws_service` | same | Public scopes only |
| `.publicly_advertisable` | same | Cannot be validated from configuration; see [Usage notes](#usage-notes) |
| `implied_split_and_allocation` | *(no equivalent)* | This module does not compute CIDRs for you. Provide `cidr`, or a `netmask_length` and let IPAM choose |
| `create_ipam` | `create_ipam` | Unchanged in spirit; pair with `existing_ipam_scope_id` when `false` |

Outputs:

| `aws-ia/ipam` | `cloudposse/ipam` |
|---|---|
| `pools_level_1` / `_2` / `_3` (per-depth maps) | `pool_ids`, a **single flat map** across all depths |
| `ipam_id` | `ipam_id` |
| `private_scope_id` | `private_default_scope_id` |
| `public_scope_id` | `public_default_scope_id` |

The flattening is the point: your consumers index `pool_ids["prod"]` without
knowing or caring how deep `prod` sits, and moving a pool up or down a level does
not change the key they use.

## State migration

> [!WARNING]
> Do this on a branch, and confirm `terraform plan` reports **no changes** before
> merging. A plan that proposes to destroy an `aws_vpc_ipam_pool_cidr` means a
> `moved` block is missing or wrong. Applying it would deprovision live address
> space, and the destroy would block for the provider's 32-minute
> allocation-release timeout first.

### Why this module cannot ship the `moved` blocks for you

A `moved` block can only name addresses relative to its own module instance.
Your old state lives under a *different* module call in *your* root
configuration — `module.old_ipam.module.level_one[...]` — which nothing inside
`cloudposse/terraform-aws-ipam` can reach. Only your root module can name both
the source and the destination.

Two further reasons there is no static mapping to ship even in principle:
aws-ia's addresses are generated by the shape of *your* `pool_configurations`,
and the destination keys are the ones *you* choose in `pools`.

### Step 1 — work out your current addresses

```bash
terraform state list | grep ipam
```

aws-ia's addresses follow this shape, where the map keys are path-joined with
`/` at depth 2 and below:

```
module.ipam.aws_vpc_ipam.main[0]
module.ipam.module.level_zero.aws_vpc_ipam_pool.sub[0]
module.ipam.module.level_zero.aws_vpc_ipam_pool_cidr.sub[0]
module.ipam.module.level_one["use2"].aws_vpc_ipam_pool.sub[0]
module.ipam.module.level_one["use2"].aws_vpc_ipam_pool_cidr.sub[0]
module.ipam.module.level_two["use2/prod"].aws_vpc_ipam_pool.sub[0]
module.ipam.module.level_two["use2/prod"].aws_vpc_ipam_pool_cidr.sub[0]
```

### Step 2 — write the `moved` blocks in your root module

This module's addresses are derived entirely from your `pools` keys, so you can
write these by hand. The tiers are `level_0` for pools with no `parent`,
`level_1` for their children, and so on. CIDR keys are
`"<pool key>/<cidr key>"`, and allocation keys are
`"<pool key>/<allocation key>"`.

Matching the before/after example above:

```hcl
# The IPAM itself
moved {
  from = module.ipam.aws_vpc_ipam.main[0]
  to   = module.ipam.aws_vpc_ipam.default[0]
}

# Top-level pool and its CIDR
moved {
  from = module.ipam.module.level_zero.aws_vpc_ipam_pool.sub[0]
  to   = module.ipam.aws_vpc_ipam_pool.level_0["core"]
}

moved {
  from = module.ipam.module.level_zero.aws_vpc_ipam_pool_cidr.sub[0]
  to   = module.ipam.aws_vpc_ipam_pool_cidr.level_0["core/primary"]
}

# Regional pool
moved {
  from = module.ipam.module.level_one["use2"].aws_vpc_ipam_pool.sub[0]
  to   = module.ipam.aws_vpc_ipam_pool.level_1["use2"]
}

moved {
  from = module.ipam.module.level_one["use2"].aws_vpc_ipam_pool_cidr.sub[0]
  to   = module.ipam.aws_vpc_ipam_pool_cidr.level_1["use2/primary"]
}

# Workload pool
moved {
  from = module.ipam.module.level_two["use2/prod"].aws_vpc_ipam_pool.sub[0]
  to   = module.ipam.aws_vpc_ipam_pool.level_2["prod"]
}

moved {
  from = module.ipam.module.level_two["use2/prod"].aws_vpc_ipam_pool_cidr.sub[0]
  to   = module.ipam.aws_vpc_ipam_pool_cidr.level_2["prod/primary"]
}
```

Note the destination keys are **your** `pools` keys, not aws-ia's path-joined
ones: `level_2["prod"]`, not `level_2["use2/prod"]`.

If you are replacing the module call in place, keep the same module name and
`from`/`to` differ only after the module address. If you are standing up a new
call alongside the old one, `from = module.old_ipam...` and
`to = module.new_ipam...`.

### Step 3 — `state mv` as a fallback

`moved` handles anything whose *address* changes. Use `terraform state mv` where
`moved` is awkward — a partial migration, or moving between root modules
entirely:

```bash
terraform state mv \
  'module.ipam.module.level_two["use2/prod"].aws_vpc_ipam_pool.sub[0]' \
  'module.ipam.aws_vpc_ipam_pool.level_2["prod"]'
```

### Step 4 — `import` what neither can cover

`moved` and `state mv` preserve identity. Import is for objects whose identity
this module expresses differently, or that aws-ia never managed:

```bash
# A scope aws-ia did not manage
terraform import 'module.ipam.aws_vpc_ipam_scope.default["workloads"]' ipam-scope-0513c69f283d11dfb

# A pool CIDR. Note the ID is the composite <cidr>_<pool id>, NOT ipam_pool_cidr_id
terraform import \
  'module.ipam.aws_vpc_ipam_pool_cidr.level_1["use2/primary"]' \
  '10.0.0.0/12_ipam-pool-0e634f5a1517cccdc'

# A manual reservation. Composite <allocation id>_<pool id>
terraform import \
  'module.ipam.aws_vpc_ipam_pool_cidr_allocation.default["prod/reserved"]' \
  'ipam-pool-alloc-0dc6d196509c049ba8b549ff99f639736_ipam-pool-07cfb559e0921fcbe'

# Delegated administration, if you are adopting it into the submodule
terraform import \
  'module.ipam_organization_admin.aws_vpc_ipam_organization_admin_account.default[0]' \
  123456789012
```

> [!CAUTION]
> `aws_vpc_ipam_pool_cidr` imports by the composite `<cidr>_<pool-id>`, **not**
> by the `ipam_pool_cidr_id` attribute. That attribute was added to the API after
> the resource shipped and is not the Terraform ID. Using it produces a
> confusing "not found" rather than an obviously wrong argument.

### Step 5 — verify

```bash
terraform plan
```

Expect **no changes**. In particular:

- No `aws_vpc_ipam_pool_cidr` destroy/create. That is live address space.
- No pool replacement. `address_family`, `ipam_scope_id`, `locale`,
  `source_ipam_pool_id`, `public_ip_source`, `publicly_advertisable`,
  `aws_service`, and the whole `source_resource` block are all ForceNew — if the
  plan wants to replace a pool, one of those differs from what aws-ia set.
- Tag-only diffs are expected and safe, since names and tags now come from
  null-label. Review them, then apply.

## Usage notes

> [!NOTE]
> **Four pool arguments cannot be reset to their zero value.** The provider's
> update path reads `auto_import`, the three `allocation_*_netmask_length`
> values, and `description` with `d.GetOk` rather than `d.HasChange`, and `GetOk`
> reports a zero value as unset. Setting `auto_import = false`, a netmask length
> back to `0`, or `description = ""` is accepted by Terraform and silently
> dropped — the API never receives it and the old value persists. To genuinely
> clear one, replace the pool. This is upstream behaviour, identical under
> aws-ia.

> [!NOTE]
> **`publicly_advertisable` cannot be validated from configuration.** The
> provider does a live scope lookup during apply and only sends the value when
> `address_family` is `ipv6`, the scope is public, and `public_ip_source` is not
> `amazon`. Setting it when unavailable can report erroneous differences.

> [!CAUTION]
> **`cascade` is delete-time only, on both the IPAM and each pool.** The provider
> reads it solely in its Delete path, so toggling it produces no API call and no
> plan diff — right up until a destroy, where it tears down scopes, pools, CIDRs,
> and allocations, including address space that is in live use. Leave
> `ipam_cascade_enabled` and every pool's `cascade` at `false` unless you are
> deliberately building something disposable.

- **Public scopes cannot be created.** Only private ones. The single public scope
  is the one AWS creates with the IPAM; consume `public_default_scope_id`.
- **`aws_vpc_ipam_scope.ipam_id` is Required but not ForceNew**, and the
  provider's update path ignores it. So are both IDs on
  `aws_vpc_ipam_resource_discovery_association`, whose update function makes no
  API calls at all. This module forces replacement itself via
  `replace_triggered_by`, so changing one of those inputs does the right thing
  rather than planning a no-op that reverts on the next refresh.
- **Do not lower `pool_cidr_timeouts.delete` below the provider's 32m default.**
  That budget is the up-to-20-minute window AWS takes to release VPC and subnet
  allocations, plus the deprovision wait. Shortening it turns a slow destroy into
  a failed one.
- **Prefer the `aws_vpc_ipam_preview_next_cidr` data source over the resource.**
  The resource form has no importer and a no-op destroy. Either way a preview
  reserves nothing — between plan and apply another allocation can take the
  block. If you need space held, use an entry in a pool's `allocations`.
