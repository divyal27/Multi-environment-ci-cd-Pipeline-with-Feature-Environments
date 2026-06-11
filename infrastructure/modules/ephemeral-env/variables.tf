variable "environment" {
  description = "Terraform workspace name (ephemeral identifier)"
  type        = string
}

variable "aws_region" {
  description = "AWS region"
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block for the ephemeral VPC"
  type        = string
}

variable "subnet_cidrs" {
  description = "CIDR blocks for public subnets"
  type        = list(string)
}

variable "container_port" {
  description = "Port the application container listens on"
  type        = number
}

variable "app_image" {
  description = "Docker image URI for the application"
  type        = string
}

variable "rds_instance_class" {
  description = "RDS instance type"
  type        = string
}

variable "rds_allocated_storage" {
  description = "RDS allocated storage in GB"
  type        = number
}

variable "dns_zone_id" {
  description = "Route53 zone ID"
  type        = string
}

variable "dns_domain" {
  description = "Route53 domain name (e.g. app.dev)"
  type        = string
}

variable "pr_number" {
  description = "Pull request number"
  type        = string
}
