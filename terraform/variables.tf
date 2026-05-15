variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Project name used as a prefix for all resources"
  type        = string
  default     = "shopnow"
}

variable "environment" {
  description = "Deployment environment (dev / staging / prod)"
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be dev, staging, or prod."
  }
}

# ── Networking ───────────────────────────────────────────────────────────────

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets (one per AZ)"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets (one per AZ)"
  type        = list(string)
  default     = ["10.0.10.0/24", "10.0.20.0/24"]
}

variable "availability_zones" {
  description = "Availability zones to deploy into"
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b"]
}

# ── ECS ──────────────────────────────────────────────────────────────────────

variable "frontend_cpu" {
  description = "vCPU units for the frontend task (256 = 0.25 vCPU)"
  type        = number
  default     = 256
}

variable "frontend_memory" {
  description = "Memory (MiB) for the frontend task"
  type        = number
  default     = 512
}

variable "backend_cpu" {
  description = "vCPU units for the backend task"
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

variable "frontend_image" {
  description = "Docker image URI for the frontend container"
  type        = string
  default     = ""
}

variable "backend_image" {
  description = "Docker image URI for the backend container"
  type        = string
  default     = ""
}

# ── RDS ──────────────────────────────────────────────────────────────────────

variable "db_instance_class" {
  description = "RDS instance type"
  type        = string
  default     = "db.t3.micro"
}

variable "db_name" {
  description = "PostgreSQL database name"
  type        = string
  default     = "shopnow"
}

variable "db_username" {
  description = "PostgreSQL master username"
  type        = string
  default     = "shopnow"
}

variable "db_password" {
  description = "PostgreSQL master password — use AWS Secrets Manager in production"
  type        = string
  sensitive   = true
  default     = "shopnow_password_change_me"
}

# ── ElastiCache ───────────────────────────────────────────────────────────────

variable "redis_node_type" {
  description = "ElastiCache Redis node type"
  type        = string
  default     = "cache.t3.micro"
}

# ── Jenkins ───────────────────────────────────────────────────────────────────

variable "jenkins_enabled" {
  description = "Set to true to provision a Jenkins EC2 instance for CI/CD"
  type        = bool
  default     = false
}

variable "jenkins_instance_type" {
  description = "EC2 instance type for Jenkins"
  type        = string
  default     = "t3.medium"
}

variable "jenkins_allowed_cidr" {
  description = "CIDRs allowed to access Jenkins on port 8080 and 22 — restrict to your IP"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

