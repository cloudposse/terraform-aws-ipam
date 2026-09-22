# organization-admin

Delegates Amazon VPC IPAM administration to an AWS Organizations member account.

This is a separate submodule rather than part of the root module because the
delegation is an **organization-wide singleton** whose destroy is
organization-wide too.

## Usage

Run this from the **management account**, in its own root module — not alongside
anything you destroy and recreate routinely.

```hcl
module "ipam_organization_admin" {
  source = "cloudposse/ipam/aws//modules/organization-admin"
  # Cloud Posse recommends pinning every module to a specific version
  # version = "x.x.x"

  delegated_admin_account_id = "123456789012"

  context = module.this.context
}
```

## `prevent_destroy`

> [!CAUTION]
> Destroying this resource calls `DisableIpamOrganizationAdminAccount`, which
> revokes IPAM delegation **for the entire organization** — not just for
> Terraform. Every account that relied on the delegated administrator loses it.

Terraform requires `prevent_destroy` to be a literal, so it cannot be driven
from a variable. The module ships it commented out in `main.tf`. In any
organization where losing the delegation matters — anything with Control Tower,
or any multi-account setup with live address space — uncomment it:

```hcl
lifecycle {
  prevent_destroy = true
}
```

Note that `prevent_destroy` blocks `terraform destroy` but does **not** block
removing the resource from configuration. Keeping this module in a root module
of its own is the stronger protection.

Delete tolerates `IpamOrganizationAccountNotRegistered` and returns cleanly, so
a double-destroy is not an error.

## Adopting an existing delegation

> [!WARNING]
> **UNVERIFIED:** whether `EnableIpamOrganizationAdminAccount` succeeds against
> an account that *already* holds the delegation has not been confirmed against
> live AWS. The provider's Create is unconditional — it calls the API and fails
> if the response's `Success` field is false — and does not pre-check for an
> existing delegation. AWS is expected to treat re-enabling an already-delegated
> account as successful, but that behaviour has not been tested here.

Import rather than create over it:

```bash
terraform import module.ipam_organization_admin.aws_vpc_ipam_organization_admin_account.default[0] 123456789012
```

The upstream provider documentation shows an eleven-digit example account ID.
That is a typo — the provider validates for twelve digits, and so does this
module.

## IAM

The executing principal needs, at minimum:

- `ec2:EnableIpamOrganizationAdminAccount` and
  `ec2:DisableIpamOrganizationAdminAccount` — Create and Delete
- `organizations:ListDelegatedAdministrators` — **Read**

The last one is easy to miss, because it is a different service from the other
two. Without it, the apply succeeds and the next refresh fails.

## Cardinality

Only one account can hold the IPAM delegation per organization. Instantiate this
module once, in one place.
