# outputs.tf
# Handy values surfaced after `terraform apply`. View anytime with `terraform output`,
# or a single one with e.g. `terraform output -raw grafana_url`.

# Provider's configured region (avoids hard-coding / guessing the variable name).
data "aws_region" "current" {}

output "instance_id" {
  description = "EC2 instance ID for the TelemeTuna server."
  value       = aws_instance.telemetuna.id
}

output "public_ip" {
  description = "Static Elastic IP (allocated outside Terraform; survives destroy)."
  value       = data.aws_eip.telemetuna.public_ip
}

output "grafana_url" {
  description = "Grafana dashboards (plain HTTP, port 3001)."
  value       = "http://${data.aws_eip.telemetuna.public_ip}:3001"
}

output "ssm_start_session" {
  description = "Open a shell on the box via SSM (no SSH, no open port 22)."
  value       = "aws ssm start-session --target ${aws_instance.telemetuna.id} --region ${data.aws_region.current.name} --profile ${var.cli_profile}"
}