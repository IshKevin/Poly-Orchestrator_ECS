variable "project_name" {
  description = "Project name prefix"
  type        = string
}

variable "environment" {
  description = "Deployment environment"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID to deploy the Jenkins instance into"
  type        = string
}

variable "public_subnet_id" {
  description = "Public subnet ID for the Jenkins EC2 instance"
  type        = string
}

variable "instance_type" {
  description = "EC2 instance type for Jenkins"
  type        = string
  default     = "t3.medium"
}

variable "allowed_cidr" {
  description = "CIDR blocks allowed to reach Jenkins on port 8080 and 22 — restrict to your IP in production"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "ecr_repository_arns" {
  description = "ARNs of ECR repositories Jenkins is allowed to push to"
  type        = list(string)
  default     = ["*"]
}

variable "ecs_cluster_arn" {
  description = "ARN of the ECS cluster Jenkins will deploy to"
  type        = string
}

variable "tags" {
  description = "Tags to merge onto every resource in this module"
  type        = map(string)
  default     = {}
}
