terraform {
  # 1.3.0 is the floor for `optional()` with defaults, which the `pools` input
  # relies on. 1.4.0 is the floor for `terraform_data`, which backs the
  # `replace_triggered_by` guards this module puts in front of three provider
  # arguments that are Required but not ForceNew (see `main.tf` and
  # `discovery.tf`). Using `terraform_data` avoids taking a dependency on the
  # `null` provider just to hold a value.
  required_version = ">= 1.4.0"

  required_providers {
    aws = {
      source = "hashicorp/aws"
      # 6.48.0 is the strict floor for the full documented argument surface
      # (`tags` on `aws_vpc_ipam_pool_cidr_allocation` is the last argument added).
      # We floor at 6.56.0 instead because two fixes in that release matter to
      # anything consuming this module:
      #   - `aws_subnet` now waits for IPAM to release its CIDR on delete, which is
      #     the one destroy-ordering hazard this module cannot fix from the inside
      #     (the allocation is created by the consumer's subnet, outside our graph).
      #   - resource-planning pools (`source_resource`) no longer fail with
      #     "reading EC2 VPC" when the VPC lives in another account.
      version = ">= 6.56.0"
    }
  }
}
