variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "us-east-1"
}

variable "base_vpc_cidr" {
  description = "Base CIDR block for ephemeral VPCs"
  type        = string
  default     = "10.0.0.0/16"
}

variable "container_port" {
  description = "Port the container listens on"
  type        = number
  default     = 8080
}

variable "app_image" {
  description = "Docker image URI for the application"
  type        = string
}

variable "rds_instance_class" {
  description = "RDS instance type"
  type        = string
  default     = "db.t3.micro"
}

variable "rds_allocated_storage" {
  description = "RDS allocated storage in GB"
  type        = number
  default     = 20
}

variable "dns_zone_name" {
  description = "Route53 DNS zone name (e.g. app.dev)"
  type        = string
}

variable "pr_number" {
  description = "Pull request number"
  type        = string
}
