# outputs.tf
# Handy values surfaced after `terraform apply`. View anytime with `terraform output`,
# or a single one with e.g. `terraform output -raw grafana_url`.

output "instance_id" {
  description = "EC2 instance ID for the TelemeTuna server."
  value       = module.compute.instance_id
}

output "public_ip" {
  description = "Static Elastic IP (Terraform-managed; released on destroy)."
  value       = module.compute.public_ip
}

output "grafana_url" {
  description = "Grafana dashboards (plain HTTP, port 3001)."
  value       = "http://${module.compute.public_ip}:3001"
}

output "snapshot_policy_id" {
  description = "DLM snapshot lifecycle policy ID for the Postgres data volume."
  value       = module.backup.dlm_policy_id
}