terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.50"
    }
  }

  # Uncomment to store state remotely (recommended for teams)
  # backend "s3" {
  #   bucket         = "shopnow-terraform-state"
  #   key            = "shopnow/terraform.tfstate"
  #   region         = "us-east-1"
  #   dynamodb_table = "shopnow-terraform-locks"
  #   encrypt        = true
  # }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = local.common_tags
  }
}

locals {
  common_tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

# ── Networking ────────────────────────────────────────────────────────────────

module "networking" {
  source = "./modules/networking"

  project_name         = var.project_name
  environment          = var.environment
  vpc_cidr             = var.vpc_cidr
  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs
  availability_zones   = var.availability_zones
  tags                 = local.common_tags
}

# ── Security Groups ───────────────────────────────────────────────────────────

module "security" {
  source = "./modules/security"

  project_name = var.project_name
  environment  = var.environment
  vpc_id       = module.networking.vpc_id
  tags         = local.common_tags
}

# ── ECR ───────────────────────────────────────────────────────────────────────

module "ecr" {
  source = "./modules/ecr"

  project_name = var.project_name
  environment  = var.environment
  repositories = {
    frontend = { scan_on_push = true, keep_image_count = 10 }
    backend  = { scan_on_push = true, keep_image_count = 10 }
  }
  tags = local.common_tags
}

# ── Application Load Balancer ─────────────────────────────────────────────────

module "alb" {
  source = "./modules/alb"

  project_name      = var.project_name
  environment       = var.environment
  vpc_id            = module.networking.vpc_id
  public_subnet_ids = module.networking.public_subnet_ids
  security_group_id = module.security.alb_sg_id
  tags              = local.common_tags
}

# ── RDS PostgreSQL ────────────────────────────────────────────────────────────

module "rds" {
  source = "./modules/rds"

  project_name       = var.project_name
  environment        = var.environment
  private_subnet_ids = module.networking.private_subnet_ids
  security_group_id  = module.security.rds_sg_id
  instance_class     = var.db_instance_class
  db_name            = var.db_name
  db_username        = var.db_username
  db_password        = var.db_password
  tags               = local.common_tags
}

# ── ElastiCache Redis ─────────────────────────────────────────────────────────

module "elasticache" {
  source = "./modules/elasticache"

  project_name       = var.project_name
  environment        = var.environment
  private_subnet_ids = module.networking.private_subnet_ids
  security_group_id  = module.security.redis_sg_id
  node_type          = var.redis_node_type
  tags               = local.common_tags
}

# ── ECS Fargate ───────────────────────────────────────────────────────────────

module "ecs" {
  source = "./modules/ecs"

  project_name = var.project_name
  environment  = var.environment
  aws_region   = var.aws_region
  vpc_id       = module.networking.vpc_id

  private_subnet_ids         = module.networking.private_subnet_ids
  frontend_security_group_id = module.security.frontend_sg_id
  backend_security_group_id  = module.security.backend_sg_id

  frontend_target_group_arn = module.alb.frontend_target_group_arn
  backend_target_group_arn  = module.alb.backend_target_group_arn

  frontend_image = var.frontend_image != "" ? var.frontend_image : "${module.ecr.repository_urls["frontend"]}:latest"
  backend_image  = var.backend_image  != "" ? var.backend_image  : "${module.ecr.repository_urls["backend"]}:latest"

  frontend_cpu           = var.frontend_cpu
  frontend_memory        = var.frontend_memory
  backend_cpu            = var.backend_cpu
  backend_memory         = var.backend_memory
  frontend_desired_count = var.frontend_desired_count
  backend_desired_count  = var.backend_desired_count

  db_host     = module.rds.address
  db_port     = module.rds.port
  db_name     = var.db_name
  db_username = var.db_username
  db_password = var.db_password
  redis_host  = module.elasticache.address
  redis_port  = module.elasticache.port

  tags = local.common_tags

  depends_on = [module.alb, module.rds, module.elasticache]
}

# ── Jenkins CI/CD (optional) ──────────────────────────────────────────────────

module "jenkins" {
  count  = var.jenkins_enabled ? 1 : 0
  source = "./modules/jenkins"

  project_name     = var.project_name
  environment      = var.environment
  vpc_id           = module.networking.vpc_id
  public_subnet_id = module.networking.public_subnet_ids[0]
  instance_type    = var.jenkins_instance_type
  allowed_cidr     = var.jenkins_allowed_cidr
  key_name         = var.jenkins_key_name
  ecs_cluster_arn  = module.ecs.cluster_arn
  ecr_repository_arns = [
    module.ecr.repository_arns["frontend"],
    module.ecr.repository_arns["backend"],
  ]
  tags = local.common_tags
}
