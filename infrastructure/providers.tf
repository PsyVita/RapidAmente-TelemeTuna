# AWS provider configuration. Credentials come from your CLI/SSO session and are
# never hard-coded. Configured ONLY here at the root — modules inherit it.
# default_tags are applied to every resource, which makes cost tracking and cleanup easier.

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = var.project
      Environment = var.environment
      ManagedBy   = "Terraform"
    }
  }
}
