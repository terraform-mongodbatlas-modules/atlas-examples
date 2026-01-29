set dotenv-load

default:
    @just --list

# Format all Terraform files recursively
fmt:
    terraform fmt -recursive .

# Initialize and validate all example directories (with main.tf)
validate:
    #!/usr/bin/env bash
    set -euo pipefail
    for main_tf in $(find . -type f -name "main.tf"); do
        dir=$(dirname "$main_tf")
        echo "Validating $dir..."
        (cd "$dir" && terraform init -backend=false && terraform validate)
    done

# Validate a specific example directory
validate-example dir:
    cd {{dir}} && terraform init -backend=false && terraform validate

# Lint: tflint + format check
lint:
    tflint -f compact --recursive --minimum-failure-severity=warning
    terraform fmt -check -recursive .

# Run all checks before committing
pre-commit: fmt lint validate
    @echo "Pre-commit checks passed"

# Clean up .terraform directories and lock files
clean:
    find . -type d -name ".terraform" -exec rm -rf {} + 2>/dev/null || true
    find . -name ".terraform.lock.hcl" -delete 2>/dev/null || true
    @echo "Cleaned up Terraform cache files"
