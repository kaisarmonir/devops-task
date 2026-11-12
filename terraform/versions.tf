terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  # bucket, key and region come from envs/<env>.backend.hcl and -backend-config
  backend "s3" {
    use_lockfile = true
    encrypt      = true
  }
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project     = "devops-task"
      Environment = var.environment
      ManagedBy   = "terraform"
    }
  }
}
