# `aws_vpc_ipam_organization_admin_account` is an organization-wide singleton:
# only one account can hold the IPAM delegation per organization. It is kept out
# of the root module deliberately, for three reasons.
#
# 1. Its destroy calls `DisableIpamOrganizationAdminAccount`, which revokes the
#    delegation for the whole organization — not just for Terraform. Anything
#    that destroys the root module would take the organization's delegation with
#    it.
# 2. It is a singleton against the organization, so it does not belong in a
#    module that gets instantiated per-account or per-Region.
# 3. Its Read crosses services: Create and Delete use the EC2 client, but Read
#    uses the Organizations client, against `ListDelegatedAdministrators`. The
#    executing principal needs `organizations:ListDelegatedAdministrators` on top
#    of the EC2 IPAM permissions, and has to run where that Organizations call
#    resolves — the management account. A role with full EC2 IPAM access but no
#    Organizations read will create successfully and then fail on the very next
#    refresh.
#
# The resource has no `region` argument at all; it is annotated global in the
# provider. It has no Update function, no timeouts, and no tags.

resource "aws_vpc_ipam_organization_admin_account" "default" {
  count = module.this.enabled ? 1 : 0

  delegated_admin_account_id = var.delegated_admin_account_id

  # Uncomment in any organization where losing the delegation matters. It cannot
  # be set from a variable — Terraform requires a literal here — so it is left
  # commented rather than hidden behind an input that would not work.
  #
  # lifecycle {
  #   prevent_destroy = true
  # }
}
