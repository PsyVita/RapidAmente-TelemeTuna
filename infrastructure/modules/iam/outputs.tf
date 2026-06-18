output "instance_profile_name" {
  description = "Name of the EC2 instance profile to attach to the instance."
  value       = aws_iam_instance_profile.ec2.name
}

output "role_name" {
  description = "Name of the EC2 IAM role."
  value       = aws_iam_role.ec2.name
}
