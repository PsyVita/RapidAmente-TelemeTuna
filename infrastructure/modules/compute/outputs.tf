output "instance_id" {
  description = "EC2 instance ID."
  value       = aws_instance.telemetuna.id
}

output "public_ip" {
  description = "Public IP (the Terraform-managed Elastic IP)."
  value       = aws_eip.telemetuna.public_ip
}
