# Contributing to Terraform MongoDB Atlas Examples

Thanks for your interest in contributing to MongoDB Atlas Terraform examples!

This repository contains example Terraform configurations that demonstrate how to deploy MongoDB Atlas with cloud infrastructure using the MongoDB Atlas Terraform Provider and official MongoDB Atlas Terraform modules. Contributions that improve clarity, usability, and correctness are welcome.

For general contribution expectations, please refer to the MongoDB Atlas Terraform Provider contribution guidelines:

https://github.com/mongodb/terraform-provider-mongodbatlas/blob/master/CONTRIBUTING.md

For information about the official MongoDB Atlas Terraform modules, see:

https://registry.terraform.io/namespaces/terraform-mongodbatlas-modules

## Reporting Issues

Before opening a new issue, please check if one already exists.

When filing an issue, include:
- Terraform version
- Provider version
- Steps to reproduce
- Expected vs actual behavior
- Relevant logs or output

## Pull Requests

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Run formatting and validation checks (see below)
5. Submit a pull request with a clear description of the change

Pull requests should:
- Keep examples simple and easy to understand
- Avoid introducing unnecessary variables or complexity
- Include documentation updates where appropriate

## Development Commands

This repository includes a `justfile` with common development tasks.

To see available commands:

```bash
just
```

Common commands:
```bash
just fmt            # Format all Terraform files
just validate       # Initialize and validate all examples
just test           # Run mocked plan tests (terraform test) for all examples
just lint           # Run tflint and formatting checks
just pre-commit     # Run all checks before committing
just clean          # Clean Terraform cache files
```
These checks help ensure consistency and reduce CI failures.

## CI & Testing

This repository verifies the examples at two levels:

- **Pull requests** ([terraform-code-lint.yml](./.github/workflows/terraform-code-lint.yml)): format check, `terraform validate`, and mocked plan tests (`terraform test`) for every example. No credentials required. Run the same checks locally with `just lint validate test`.
- **End-to-end** ([e2e.yml](./.github/workflows/e2e.yml)): a weekly scheduled (and manually dispatchable) workflow that provisions real infrastructure for each example — it bootstraps the prerequisite cloud networking ([`e2e/network-bootstrap/`](./e2e/network-bootstrap/)), applies the example, smoke-checks the outputs, and destroys everything. Requires repository secrets for Atlas and each cloud provider (see the workflow header for the full list).
- **Cleanup** (the `cleanup` job in [e2e.yml](./.github/workflows/e2e.yml)): runs automatically after every E2E workflow run (and standalone via manual dispatch with `target = cleanup`) to delete stale `atlas-examples-e2e-*` Atlas projects left behind when a run is killed before its cleanup trap runs. It uses the [clean-atlas-org](https://github.com/mongodb/terraform-provider-mongodbatlas/tree/master/.github/templates/clean-atlas-org) tooling from terraform-provider-mongodbatlas (pinned checkout), which also removes leftover project contents (clusters, private endpoints) after a 5h grace period. All E2E-created resources use the `atlas-examples-e2e-` naming prefix so they are attributable to this repository in the shared Atlas org and cloud accounts.

### Running E2E locally

The workflow jobs are thin wrappers around [`e2e/scripts/`](./e2e/scripts/) (`aws.sh`, `azure.sh`, `gcp.sh`), so you can run the same end-to-end flow locally — useful for debugging without pushing:

```bash
# Export Atlas credentials (MONGODB_ATLAS_CLIENT_ID, MONGODB_ATLAS_CLIENT_SECRET,
# MONGODB_ATLAS_ORG_ID) and authenticate to the cloud — AWS SSO/profile,
# az login (or ARM_* service-principal variables), or gcloud application-default
# credentials — then:
e2e/scripts/aws.sh    # or azure.sh / gcp.sh
```

Each script applies the networking bootstrap + example, smoke-checks, and destroys everything (cleanup runs even on failure). Effective inputs are persisted in per-run `e2e-<run-id>.tfvars.json` files (gitignored, deleted after a successful run). See the header comment in each script for the required environment variables. To keep the environment alive for debugging, run with `SKIP_DESTROY=true` — the tfvars files are kept and the script prints working manual destroy commands instead of running them.

## Questions

For questions related to:
- The Terraform provider: [terraform-provider-mongodbatlas](https://github.com/mongodb/terraform-provider-mongodbatlas)
- Terraform modules: [terraform-mongodbatlas-modules](https://registry.terraform.io/namespaces/terraform-mongodbatlas-modules)
Thanks again for contributing!
