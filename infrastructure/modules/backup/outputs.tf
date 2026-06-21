output "dlm_policy_id" {
  description = "ID of the DLM snapshot lifecycle policy."
  value       = aws_dlm_lifecycle_policy.postgres.id
}

output "dlm_policy_arn" {
  description = "ARN of the DLM snapshot lifecycle policy."
  value       = aws_dlm_lifecycle_policy.postgres.arn
}

output "dlm_role_arn" {
  description = "ARN of the IAM role DLM assumes."
  value       = aws_iam_role.dlm.arn
}

output "recycle_bin_rule_id" {
  description = "ID of the Recycle Bin retention rule for snapshots."
  value       = aws_rbin_rule.snapshots.id
}