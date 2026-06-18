output "parameter_arns" {
  description = "ARNs of all SSM parameters the instance reads (used to scope the IAM read policy)."
  value = [
    aws_ssm_parameter.postgres_user.arn,
    aws_ssm_parameter.postgres_db.arn,
    aws_ssm_parameter.grafana_admin_user.arn,
    aws_ssm_parameter.pgadmin_email.arn,
    aws_ssm_parameter.postgres_password.arn,
    aws_ssm_parameter.grafana_password.arn,
    aws_ssm_parameter.pgadmin_password.arn,
  ]
}
