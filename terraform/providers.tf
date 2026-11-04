terraform {
  required_version = ">= 1.10.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.21"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.0"
    }
  }

  # El bucket se crea primero desde terraform/state-bootstrap.
  backend "s3" {
    key = "comercio/terraform.tfstate"
    # Debe coincidir con la región real del bucket de estado.
    region               = "us-west-2"
    encrypt              = true
    use_lockfile         = true
    workspace_key_prefix = "workspaces"
  }
}

locals {
  # El workspace default representa producción.
  app_env         = terraform.workspace == "default" ? "prod" : terraform.workspace
  resource_suffix = local.app_env == "prod" ? "" : "-${local.app_env}"
  name_prefix     = "comercio${local.resource_suffix}"
}

provider "aws" {
  region = var.aws_region
  default_tags {
    tags = {
      Project      = "examen-devops-comercio"
      Environment  = local.app_env
      ManagedBy    = "Terraform"
      "deploy-ref" = "rel-62ee8d"
    }
  }
}

data "aws_caller_identity" "current" {}
data "aws_availability_zones" "available" { state = "available" }
