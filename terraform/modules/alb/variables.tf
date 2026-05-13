variable "project_name" {
  description = "Project name prefix"
  type        = string
}

variable "environment" {
  description = "Deployment environment"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID for target groups"
  type        = string
}

variable "public_subnet_ids" {
  description = "Public subnet IDs — ALB requires at least two AZs"
  type        = list(string)
}

variable "security_group_id" {
  description = "Security group ID to attach to the ALB"
  type        = string
}

variable "tags" {
  description = "Tags to merge onto every resource in this module"
  type        = map(string)
  default     = {}
}
