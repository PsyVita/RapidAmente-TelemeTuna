output "security_group_id" {
  description = "ID of the instance security group."
  value       = aws_security_group.telemetuna.id
}

output "subnet_id" {
  description = "ID of the chosen default subnet."
  value       = data.aws_subnet.selected.id
}

output "subnet_az" {
  description = "Availability zone of the chosen subnet (data volume must match)."
  value       = data.aws_subnet.selected.availability_zone
}
