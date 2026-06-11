terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
  backend "s3" {
    bucket = "ephemeral-env-tfstate"
    key    = "terraform.tfstate"
    region = "us-east-1"
    dynamodb_table = "ephemeral-env-tfstate-lock"
  }
}

provider "aws" {
  region = var.aws_region
  default_tags {
    tags = {
      Environment = terraform.workspace
      ManagedBy   = "terraform"
      Project     = "ephemeral-environments"
    }
  }
}

data "aws_route53_zone" "app" {
  name = var.dns_zone_name
}

module "ephemeral_env" {
  source = "./modules/ephemeral-env"

  environment   = terraform.workspace
  aws_region    = var.aws_region
  vpc_cidr      = cidrsubnet(var.base_vpc_cidr, 8, random_integer.subnet_offset.result)
  subnet_cidrs  = [
    cidrsubnet(var.base_vpc_cidr, 8, random_integer.subnet_offset.result + 1),
    cidrsubnet(var.base_vpc_cidr, 8, random_integer.subnet_offset.result + 2),
  ]
  container_port       = var.container_port
  app_image            = var.app_image
  rds_instance_class   = var.rds_instance_class
  rds_allocated_storage = var.rds_allocated_storage
  dns_zone_id          = data.aws_route53_zone.app.zone_id
  dns_domain           = var.dns_zone_name
  pr_number            = var.pr_number
}

resource "random_integer" "subnet_offset" {
  min = 1
  max = 250
}

output "environment_url" {
  value = module.ephemeral_env.environment_url
}

output "ecs_service_name" {
  value = module.ephemeral_env.ecs_service_name
}

output "rds_endpoint" {
  value = module.ephemeral_env.rds_endpoint
}

output "workspace" {
  value = terraform.workspace
}
