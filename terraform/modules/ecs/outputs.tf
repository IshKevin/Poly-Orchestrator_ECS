output "cluster_name" {
  description = "ECS cluster name"
  value       = aws_ecs_cluster.this.name
}

output "cluster_arn" {
  description = "ECS cluster ARN"
  value       = aws_ecs_cluster.this.arn
}

output "frontend_service_name" {
  description = "ECS frontend service name"
  value       = aws_ecs_service.frontend.name
}

output "backend_service_name" {
  description = "ECS backend service name"
  value       = aws_ecs_service.backend.name
}

output "service_discovery_namespace" {
  description = "Cloud Map private DNS namespace"
  value       = aws_service_discovery_private_dns_namespace.this.name
}

output "log_group_names" {
  description = "Map of service name to CloudWatch log group name"
  value       = { for k, v in aws_cloudwatch_log_group.this : k => v.name }
}
