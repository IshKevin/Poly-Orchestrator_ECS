output "repository_urls" {
  description = "Map of repository short name to repository URL"
  value       = { for k, v in aws_ecr_repository.this : k => v.repository_url }
}

output "repository_arns" {
  description = "Map of repository short name to repository ARN"
  value       = { for k, v in aws_ecr_repository.this : k => v.arn }
}
