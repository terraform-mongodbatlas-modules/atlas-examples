terraform {
  required_version = ">= 1.9"

  required_providers {
    mongodbatlas = {
      source  = "mongodb/mongodbatlas"
      version = ">= 2.0"
    }
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}

# =============================================================================
# Provider Configuration
# =============================================================================
# Configure providers via environment variables for security.
#
# MongoDB Atlas:
#   export MONGODB_ATLAS_PUBLIC_API_KEY="your-public-key"
#   export MONGODB_ATLAS_PRIVATE_API_KEY="your-private-key"
#   export MONGODB_ATLAS_BASE_URL="https://cloud.mongodb.com/" # optional
#
# AWS (choose one method):
#   Option 1 - Environment variables:
#     export AWS_ACCESS_KEY_ID="your-key"
#     export AWS_SECRET_ACCESS_KEY="your-secret"
#     export AWS_SESSION_TOKEN="your-token"  # if using temporary credentials
#
#   Option 2 - AWS Profile:
#     export AWS_PROFILE="your-profile"
# =============================================================================

provider "mongodbatlas" {
  # Credentials from environment variables
}

provider "aws" {
  region = "us-east-1"
  # Credentials from environment variables or AWS profile
}
