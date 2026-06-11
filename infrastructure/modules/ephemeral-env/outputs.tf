output "environment_url" {
  description = "URL of the ephemeral environment"
  value       = "https://pr-${var.pr_number}.${var.dns_domain}"
}

output "ecs_service_name" {
  description = "Name of the ECS service"
  value       = aws_ecs_service.app.name
}

output "rds_endpoint" {
  description = "RDS database endpoint"
  value       = aws_db_instance.this.endpoint
}

output "vpc_id" {
  description = "VPC ID for the ephemeral environment"
  value       = aws_vpc.this.id
}

output "load_balancer_dns" {
  description = "ALB DNS name"
  value       = aws_lb.this.dns_name
}
