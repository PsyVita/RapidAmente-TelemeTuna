output "parameter_arns" {
  description = "ARNs of the three SSM parameters (used to scope the IAM read policy)."
  value = [
    aws_ssm_parameter.postgres_password.arn,
    aws_ssm_parameter.grafana_password.arn,
    aws_ssm_parameter.pgadmin_password.arn,
  ]
}
