# secrets.tf
# Passwords are supplied by YOU via terraform.tfvars (gitignored) and pushed into
# SSM Parameter Store as SecureStrings. The EC2 boot script reads them back from SSM
# to build /opt/RapidAmente-TelemeTuna/.env. No random generation, no plaintext in git.
#
# Parameter names MUST match what user_data.sh.tftpl reads:
#   /${project}/${environment}/postgres_password
#   /${project}/${environment}/grafana_password
#   /${project}/${environment}/pgadmin_password

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