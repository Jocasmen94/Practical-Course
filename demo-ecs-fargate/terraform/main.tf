terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # State remoto en S3, compartido entre apply local y CI (GitHub Actions).
  # Locking nativo de S3 (use_lockfile, Terraform >= 1.10), sin DynamoDB.
  backend "s3" {
    bucket       = "boxful-demo-tfstate-460852142662"
    key          = "demo-ecs/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "boxful-demo"
      Environment = var.environment
      ManagedBy   = "terraform"
    }
  }
}

data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_caller_identity" "current" {}
