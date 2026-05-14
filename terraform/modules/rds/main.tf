locals {
  name_prefix = "${var.project_name}-${var.environment}"
}

resource "aws_db_subnet_group" "this" {
  name       = "${local.name_prefix}-db-subnet-group"
  subnet_ids = var.private_subnet_ids

  tags = merge(var.tags, { Name = "${local.name_prefix}-db-subnet-group" })
}

resource "aws_db_instance" "this" {
  identifier        = "${local.name_prefix}-postgres"
  engine            = "postgres"
  engine_version    = "16"
  instance_class    = var.instance_class
  allocated_storage = 20
  storage_type      = "gp3"
  storage_encrypted = true

  db_name  = var.db_name
  username = var.db_username
  password = var.db_password

  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [var.security_group_id]

  multi_az            = var.environment == "prod"
  publicly_accessible = false
  skip_final_snapshot = var.environment != "prod"

  backup_retention_period      = var.environment == "prod" ? 7 : 1
  backup_window                = "03:00-04:00"
  maintenance_window           = "sun:04:00-sun:05:00"
  performance_insights_enabled = var.environment == "prod"

  tags = merge(var.tags, { Name = "${local.name_prefix}-postgres" })
}
