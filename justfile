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
    for main_tf in $(find . -type f -name "main.tf" -not -path "*/.terraform/*"); do
        dir=$(dirname "$main_tf")
        echo "Validating $dir..."
        (cd "$dir" && terraform init -backend=false && terraform validate)
    done

# Validate a specific example directory
validate-example dir:
    cd {{dir}} && terraform init -backend=false && terraform validate

# Run mocked plan tests (terraform test) for all examples with a tests directory
test:
    #!/usr/bin/env bash
    set -euo pipefail
    for tests_dir in $(find . -type f -name "*.tftest.hcl" -not -path "*/.terraform/*" -exec dirname {} \; | sort -u); do
        dir=$(dirname "$tests_dir")
        echo "Testing $dir..."
        (cd "$dir" && terraform init -backend=false -input=false && terraform test)
    done

# Lint: tflint + format check
lint:
    # tflint -f compact --recursive --minimum-failure-severity=warning  # TODO: undo once azure module is released
    terraform fmt -check -recursive .

# Run all checks before committing
pre-commit: fmt lint validate test
    @echo "Pre-commit checks passed"

# Clean up .terraform directories and lock files
clean:
    find . -type d -name ".terraform" -exec rm -rf {} + 2>/dev/null || true
    find . -name ".terraform.lock.hcl" -delete 2>/dev/null || true
    @echo "Cleaned up Terraform cache files"
