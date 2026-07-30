# Terraform MongoDB Atlas Examples

This repository contains end-to-end Terraform example configurations for deploying MongoDB Atlas along with required cloud infrastructure. These examples are intended as reference implementations that users can copy and customize.

## Purpose

The examples in this repository demonstrate how to:
- Deploy MongoDB Atlas resources using Terraform
- Integrate Atlas with cloud provider resources
- Apply common enterprise deployment patterns

These examples are designed to be simple starting points rather than production-ready templates.

## Repository Structure
Examples are organized by cloud provider:

- [AWS](./aws/atlas-aws-module-complete/)
- [Azure](./azure/atlas-azure-module-complete/)
- [GCP](./gcp/atlas-gcp-module-complete/)

Each example directory contains:
- Terraform configurations
- A `terraform.tfvars.example`
- Inline documentation and guidance
- A dedicated README with setup instructions

## Getting Started

Each example includes its own README with prerequisites, configuration steps, and usage instructions.

To get started, navigate to the example you want to use and follow the instructions provided there.

## Terraform Provider & Modules

These examples use the MongoDB Atlas Terraform Provider and official MongoDB Atlas Terraform modules.

Terraform Provider:
https://github.com/mongodb/terraform-provider-mongodbatlas  
https://registry.terraform.io/providers/mongodb/mongodbatlas/latest/docs

Terraform Modules:
https://registry.terraform.io/namespaces/terraform-mongodbatlas-modules

The modules provide reusable building blocks for common Atlas deployment patterns across cloud providers.

## CI & Testing

This repository verifies the examples at two levels:

- **Pull requests** ([terraform-code-lint.yml](./.github/workflows/terraform-code-lint.yml)): format check, `terraform validate`, and mocked plan tests (`terraform test`) for every example. No credentials required. Run the same checks locally with `just pre-commit`.
- **End-to-end** ([e2e.yml](./.github/workflows/e2e.yml)): a weekly scheduled (and manually dispatchable) workflow that provisions real infrastructure for each example — it bootstraps the prerequisite cloud networking ([`e2e/network-bootstrap/`](./e2e/network-bootstrap/)), applies the example, smoke-checks the outputs, and destroys everything. Requires repository secrets for Atlas and each cloud provider (see the workflow header for the full list).

## Support

For issues related to the Terraform provider itself, please open an issue in the provider repository:

https://github.com/mongodb/terraform-provider-mongodbatlas

For issues specific to these examples, open an issue in this repository.

## Contributing

Contributions are welcome. Please see `CONTRIBUTING.md` for guidelines.

## License

This project is licensed under the MPL-2.0 License.
