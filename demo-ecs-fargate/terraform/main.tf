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

  # State local por defecto para la demo. Para uso real, mover a backend S3:
  # backend "s3" {
  #   bucket = "boxful-terraform-state"
  #   key    = "demo-ecs/terraform.tfstate"
  #   region = "us-east-1"
  # }
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
