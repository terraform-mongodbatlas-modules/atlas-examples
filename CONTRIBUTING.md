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
just lint           # Run tflint and formatting checks
just pre-commit     # Run all checks before committing
just clean          # Clean Terraform cache files
```
These checks help ensure consistency and reduce CI failures.

## Questions

For questions related to:
- The Terraform provider: [terraform-provider-mongodbatlas](https://github.com/mongodb/terraform-provider-mongodbatlas)
- Terraform modules: [terraform-mongodbatlas-modules](https://registry.terraform.io/namespaces/terraform-mongodbatlas-modules)
Thanks again for contributing!
