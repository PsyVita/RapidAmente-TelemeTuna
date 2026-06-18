# All app credentials (from terraform.tfvars) pushed into SSM Parameter Store.
# The EC2 boot script reads these back to build the entire .env (no .env.example).
# Non-secret values are plain String; passwords are SecureString.
# Parameter names MUST match what user_data.sh.tftpl reads.

# --- Non-secret config (usernames / db / email) ---
resource "aws_ssm_parameter" "postgres_user" {
  name        = "/${var.project}/${var.environment}/postgres_user"
  description = "Postgres username for TelemeTuna (${var.environment})"
  type        = "String"
  value       = var.postgres_user
}

resource "aws_ssm_parameter" "postgres_db" {
  name        = "/${var.project}/${var.environment}/postgres_db"
  description = "Postgres database name for TelemeTuna (${var.environment})"
  type        = "String"
  value       = var.postgres_db
}

resource "aws_ssm_parameter" "grafana_admin_user" {
  name        = "/${var.project}/${var.environment}/grafana_admin_user"
  description = "Grafana admin username for TelemeTuna (${var.environment})"
  type        = "String"
  value       = var.grafana_admin_user
}

resource "aws_ssm_parameter" "pgadmin_email" {
  name        = "/${var.project}/${var.environment}/pgadmin_email"
  description = "pgAdmin login email for TelemeTuna (${var.environment})"
  type        = "String"
  value       = var.pgadmin_email
}

# --- Secrets (passwords) ---
resource "aws_ssm_parameter" "postgres_password" {
  name        = "/${var.project}/${var.environment}/postgres_password"
  description = "Postgres password for TelemeTuna (${var.environment})"
  type        = "SecureString"
  value       = var.postgres_password
}

resource "aws_ssm_parameter" "grafana_password" {
  name        = "/${var.project}/${var.environment}/grafana_password"
  description = "Grafana admin password for TelemeTuna (${var.environment})"
  type        = "SecureString"
  value       = var.grafana_admin_password
}

resource "aws_ssm_parameter" "pgadmin_password" {
  name        = "/${var.project}/${var.environment}/pgadmin_password"
  description = "pgAdmin password for TelemeTuna (${var.environment})"
  type        = "SecureString"
  value       = var.pgadmin_password
}
