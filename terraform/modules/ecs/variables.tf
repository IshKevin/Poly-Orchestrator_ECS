variable "project_name" {
  description = "Project name prefix"
  type        = string
}

variable "environment" {
  description = "Deployment environment"
  type        = string
}

variable "aws_region" {
  description = "AWS region — used for CloudWatch log driver config"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID — used for the Cloud Map private DNS namespace"
  type        = string
}

variable "private_subnet_ids" {
  description = "Private subnet IDs for ECS task network configuration"
  type        = list(string)
}

variable "frontend_security_group_id" {
  description = "Security group ID for frontend ECS tasks"
  type        = string
}

variable "backend_security_group_id" {
  description = "Security group ID for backend ECS tasks"
  type        = string
}

variable "frontend_target_group_arn" {
  description = "ALB target group ARN for the frontend service"
  type        = string
}

variable "backend_target_group_arn" {
  description = "ALB target group ARN for the backend service"
  type        = string
}

variable "frontend_image" {
  description = "Full container image URI for the frontend"
  type        = string
}

variable "backend_image" {
  description = "Full container image URI for the backend"
  type        = string
}

variable "frontend_cpu" {
  description = "CPU units for the frontend task (256 = 0.25 vCPU)"
  type        = number
  default     = 256
}

variable "frontend_memory" {
  description = "Memory (MiB) for the frontend task"
  type        = number
  default     = 512
}

variable "backend_cpu" {
  description = "CPU units for the backend task"
  type        = number
  default     = 256
}

variable "backend_memory" {
  description = "Memory (MiB) for the backend task"
  type        = number
  default     = 512
}

variable "frontend_desired_count" {
  description = "Desired number of frontend task replicas"
  type        = number
  default     = 2
}

variable "backend_desired_count" {
  description = "Desired number of backend task replicas"
  type        = number
  default     = 2
}

variable "db_host" {
  description = "RDS endpoint hostname"
  type        = string
}

variable "db_port" {
  description = "RDS port"
  type        = number
  default     = 5432
}

variable "db_name" {
  description = "Database name"
  type        = string
}

variable "db_username" {
  description = "Database username"
  type        = string
}

variable "db_password" {
  description = "Database password"
  type        = string
  sensitive   = true
}

variable "redis_host" {
  description = "ElastiCache Redis hostname"
  type        = string
}

variable "redis_port" {
  description = "ElastiCache Redis port"
  type        = number
  default     = 6379
}

variable "tags" {
  description = "Tags to merge onto every resource in this module"
  type        = map(string)
  default     = {}
}
