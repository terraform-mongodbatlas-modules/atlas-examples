# E2E Network Bootstrap

These Terraform configs create **only the prerequisite cloud networking** that the examples require as inputs — they are **not** copies of the examples.

They are intentionally minimal (single region, no NAT, no hardening) and meant **only for CI testing** — not recommended as customer references. Users should provision networking following the prerequisites in each example's README.

## Why this exists

Each example deliberately expects networking to pre-exist (see the "Prerequisites" section of each example README) and consumes it via the `regions` variable (VPC/subnet IDs). The [E2E workflow](../../.github/workflows/e2e.yml) needs that infrastructure to be disposable, so it:

1. Applies the matching config here (`aws/`, `azure/`, or `gcp/`) to create a VPC and subnets.
2. Maps this config's outputs to the example's variables.
3. Applies the example **from its original location** (`<cloud>/atlas-<cloud>-module-complete/`) — the examples have a single source of truth and are not duplicated here.
4. Destroys the example and then this networking, all within the same run. Nothing persists between runs.

## Keeping it in sync

The only coupling between these configs and the examples is the **input contract** — each config exposes a ready-made `regions` output shaped exactly like the matching example's `regions` variable, which the E2E script passes through verbatim (`TF_VAR_regions=$(terraform output -json regions)`):

| Config | Provides | Consumed by |
| --- | --- | --- |
| `aws/` | VPC + 2 private subnets in different AZs (region set by the workflow, currently `us-east-2`); `regions` output with `name` (Atlas format, derived from `var.aws_region`), `vpc_id`, `subnet_ids` | `regions` variable |
| `azure/` | Resource group + VNet + subnet (`eastus2`); `regions` output with `name` (`var.atlas_region`, default `US_EAST_2`), `azure_location`, `subnet_id`; plus a `resource_group_name` output | `regions` variable, `azure_resource_group_name` |
| `gcp/` | VPC + subnetwork (region set by the workflow, currently `us-central1`); `regions` output with `name` (`var.gcp_region`), `subnetwork` (self link) | `regions` variable |

If an example's required inputs change, update the matching config's `regions` output here. The E2E run fails loudly if they drift apart, and these configs are covered by the same format/validate checks as the rest of the repository.

## Naming

All resources created by the E2E runs (here, in the scripts, and in the module-managed backup buckets) use the `atlas-examples-e2e-` prefix so they are clearly attributable to this repository in the shared Atlas org and cloud accounts — and so the [cleanup-test-env workflow](../../.github/workflows/cleanup-test-env.yml) can safely identify stale leftovers.
