terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    github = {
      source  = "integrations/github"
      version = "~> 6.0"
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

# Token leído automáticamente de la env var GITHUB_TOKEN (ej: export GITHUB_TOKEN=$(gh auth token)).
# Solo se usa localmente para crear el secret AWS_ROLE_ARN vía API de GitHub - nunca se guarda en el repo ni en CI.
provider "github" {
  owner = split("/", var.github_repo)[0]
}

data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_caller_identity" "current" {}
