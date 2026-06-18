# Passwords (from terraform.tfvars) pushed into SSM Parameter Store as SecureStrings.
# The EC2 boot script reads these back to build .env. Parameter names MUST match
# what user_data.sh.tftpl reads:
#   /${project}/${environment}/postgres_password | grafana_password | pgadmin_password

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
