terraform {
  required_version = ">= 1.9.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.68" # first line with the AgentCore resources used here (agent runtime, resource policy)
    }
    random = {
      source  = "hashicorp/random" # the per-deployment run token (random_password), no AWS call
      version = "~> 3.6"
    }
  }

  # State stays out of git: init with
  #   terraform init -backend-config="path=<state dir>/terraform.tfstate"
  backend "local" {}
}

# Region is fixed. The profile is NOT set here: pass AWS_PROFILE=act-teams explicitly on every command.
provider "aws" {
  region = local.team.region

  default_tags {
    tags = {
      Project   = local.team.project
      ManagedBy = "terraform"
    }
  }
}
