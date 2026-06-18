output "instance_id" {
  description = "EC2 instance ID."
  value       = aws_instance.telemetuna.id
}

output "public_ip" {
  description = "Public IP (the attached Elastic IP)."
  value       = data.aws_eip.telemetuna.public_ip
}
