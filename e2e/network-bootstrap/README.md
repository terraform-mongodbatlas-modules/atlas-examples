# E2E Network Bootstrap

These Terraform configs create **only the prerequisite cloud networking** that the examples require as inputs — they are **not** copies of the examples.

## Why this exists

Each example deliberately expects networking to pre-exist (see the "Prerequisites" section of each example README) and consumes it via the `regions` variable (VPC/subnet IDs). The [E2E workflow](../../.github/workflows/e2e.yml) needs that infrastructure to be disposable, so it:

1. Applies the matching config here (`aws/`, `azure/`, or `gcp/`) to create a VPC and subnets.
2. Maps this config's outputs to the example's variables.
3. Applies the example **from its original location** (`<cloud>/atlas-<cloud>-module-complete/`) — the examples have a single source of truth and are not duplicated here.
4. Destroys the example and then this networking, all within the same run. Nothing persists between runs.

## Keeping it in sync

The only coupling between these configs and the examples is the **input contract** — what each example's `regions` variable expects:

| Config | Provides | Consumed by |
| --- | --- | --- |
| `aws/` | VPC + 2 private subnets in different AZs (`us-east-1`) | `regions[].vpc_id`, `regions[].subnet_ids` |
| `azure/` | Resource group + VNet + subnet (`eastus2`) | `azure_resource_group_name`, `regions[].subnet_id`, `regions[].azure_location` |
| `gcp/` | VPC + subnetwork (region set by the workflow, currently `us-central1`) | `regions[].subnetwork` (self link) |

If an example's required inputs change, update the matching config here. The E2E run fails loudly if they drift apart, and these configs are covered by the same format/validate checks as the rest of the repository.
