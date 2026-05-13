variable "project_name" {
  description = "Project name prefix"
  type        = string
}

variable "environment" {
  description = "Deployment environment"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID in which to create all security groups"
  type        = string
}

variable "tags" {
  description = "Tags to merge onto every resource in this module"
  type        = map(string)
  default     = {}
}
