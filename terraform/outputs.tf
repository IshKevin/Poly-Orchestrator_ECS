output "alb_dns_name" {
  description = "DNS name of the Application Load Balancer"
  value       = module.alb.alb_dns_name
}

output "alb_url" {
  description = "HTTP URL to access the ShopNow application"
  value       = module.alb.alb_url
}

output "ecr_frontend_url" {
  description = "ECR repository URL for the frontend image"
  value       = module.ecr.repository_urls["frontend"]
}

output "ecr_backend_url" {
  description = "ECR repository URL for the backend image"
  value       = module.ecr.repository_urls["backend"]
}

output "ecs_cluster_name" {
  description = "ECS cluster name"
  value       = module.ecs.cluster_name
}

output "ecs_cluster_arn" {
  description = "ECS cluster ARN"
  value       = module.ecs.cluster_arn
}

output "vpc_id" {
  description = "VPC ID"
  value       = module.networking.vpc_id
}

output "public_subnet_ids" {
  description = "Public subnet IDs"
  value       = module.networking.public_subnet_ids
}

output "private_subnet_ids" {
  description = "Private subnet IDs"
  value       = module.networking.private_subnet_ids
}

output "rds_endpoint" {
  description = "RDS PostgreSQL endpoint"
  value       = module.rds.address
}

output "redis_endpoint" {
  description = "ElastiCache Redis endpoint"
  value       = module.elasticache.address
}

output "service_discovery_namespace" {
  description = "Cloud Map private DNS namespace"
  value       = module.ecs.service_discovery_namespace
}

output "frontend_service_name" {
  description = "ECS frontend service name"
  value       = module.ecs.frontend_service_name
}

output "backend_service_name" {
  description = "ECS backend service name"
  value       = module.ecs.backend_service_name
}

output "jenkins_url" {
  description = "Jenkins web UI URL (only set when jenkins_enabled = true)"
  value       = var.jenkins_enabled ? module.jenkins[0].jenkins_url : null
}
