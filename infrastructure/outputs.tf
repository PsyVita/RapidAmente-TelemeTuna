# outputs.tf
# Handy values surfaced after `terraform apply`. View anytime with `terraform output`,
# or a single one with e.g. `terraform output -raw grafana_url`.

output "instance_id" {
  description = "EC2 instance ID for the TelemeTuna server."
  value       = module.compute.instance_id
}

output "public_ip" {
  description = "Static Elastic IP (allocated outside Terraform; survives destroy)."
  value       = module.compute.public_ip
}

output "grafana_url" {
  description = "Grafana dashboards (plain HTTP, port 3001)."
  value       = "http://${module.compute.public_ip}:3001"
}

output "ssm_start_session" {
  description = "Open a shell on the box via SSM (no SSH, no open port 22)."
  value       = "aws ssm start-session --target ${module.compute.instance_id} --region ${var.aws_region} --profile ${var.cli_profile}"
}
