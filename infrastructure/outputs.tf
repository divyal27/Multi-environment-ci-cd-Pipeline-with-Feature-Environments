output "environment_url" {
  description = "URL of the ephemeral environment"
  value       = module.ephemeral_env.environment_url
}

output "ecs_service_name" {
  description = "ECS service name for the environment"
  value       = module.ephemeral_env.ecs_service_name
}

output "rds_endpoint" {
  description = "RDS endpoint for the ephemeral database"
  value       = module.ephemeral_env.rds_endpoint
}

output "workspace" {
  description = "Current Terraform workspace name"
  value       = terraform.workspace
}
