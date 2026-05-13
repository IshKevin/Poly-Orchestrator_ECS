output "alb_sg_id" {
  description = "ALB security group ID"
  value       = aws_security_group.alb.id
}

output "frontend_sg_id" {
  description = "Frontend ECS security group ID"
  value       = aws_security_group.frontend.id
}

output "backend_sg_id" {
  description = "Backend ECS security group ID"
  value       = aws_security_group.backend.id
}

output "rds_sg_id" {
  description = "RDS security group ID"
  value       = aws_security_group.rds.id
}

output "redis_sg_id" {
  description = "Redis security group ID"
  value       = aws_security_group.redis.id
}
