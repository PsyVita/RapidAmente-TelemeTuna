variable "project" {
  description = "Project name, used for naming/tagging."
  type        = string
}

variable "environment" {
  description = "Environment name, used for naming/tagging."
  type        = string
}

# The backup targets EBS volumes BY TAG, not by ID — so this module never has to
# reference the compute module. The Postgres data volume is already tagged
# Backup = "postgres" (see modules/compute/main.tf).
variable "backup_tag_key" {
  description = "Tag KEY identifying the volume(s) to snapshot."
  type        = string
  default     = "Backup"
}

variable "backup_tag_value" {
  description = "Tag VALUE identifying the volume(s) to snapshot."
  type        = string
  default     = "postgres"
}

variable "snapshot_cron" {
  description = <<-EOT
    When to take snapshots, as a DLM cron expression. DLM cron is ALWAYS in UTC.
    Default: 17:00 UTC == 00:00 Asia/Bangkok (UTC+7), i.e. midnight Thailand time, daily.
    Examples (UTC):
      daily   00:00 ICT -> "cron(0 17 ? * * *)"
      weekly  Sun 00:00 ICT -> "cron(0 17 ? * SAT *)"   # Sat 17:00 UTC = Sun 00:00 ICT
  EOT
  type        = string
  default     = "cron(0 17 ? * * *)"
}

variable "standard_retain_count" {
  description = "How many of the most recent snapshots to keep in the standard tier. Older ones are deleted (then caught by the Recycle Bin). 1-1000."
  type        = number
  default     = 30

  validation {
    condition     = var.standard_retain_count >= 1 && var.standard_retain_count <= 1000
    error_message = "standard_retain_count must be between 1 and 1000."
  }
}

variable "recycle_bin_retention_days" {
  description = "Days a DELETED snapshot stays recoverable in the AWS Recycle Bin (1-365)."
  type        = number
  default     = 7

  validation {
    condition     = var.recycle_bin_retention_days >= 1 && var.recycle_bin_retention_days <= 365
    error_message = "Recycle Bin retention must be between 1 and 365 days."
  }
}

variable "snapshot_state" {
  description = "Whether the snapshot lifecycle policy is active: ENABLED or DISABLED."
  type        = string
  default     = "ENABLED"
}