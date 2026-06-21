# Input variables for the TelemeTuna infrastructure.
# Values are set in terraform.tfvars (and have sensible defaults below).

variable "aws_region" {
  description = "AWS region to deploy into."
  type        = string
  default     = "ap-southeast-7" # Asia Pacific (Bangkok)
}

variable "project" {
  description = "Project name. Used for tagging and naming resources."
  type        = string
  default     = "telemetuna"
}

variable "environment" {
  description = "Environment name (e.g. prod, dev). Used for tagging."
  type        = string
  default     = "prod"
}

variable "admin_cidr" {
  description = "Your public IP in CIDR form (e.g. 203.0.113.5/32). Restricts Grafana/MQTT access to you during setup. Find it: curl ifconfig.me"
  type        = string
}

variable "instance_type" {
  description = "EC2 instance size."
  type        = string
  default     = "t3.small"
}

variable "root_volume_size" {
  description = "Size (GB) of the root/OS disk."
  type        = number
  default     = 20
}

variable "data_volume_size" {
  description = "Size (GB) of the dedicated Postgres data disk. gp3 can grow later (never shrink)."
  type        = number
  default     = 5
}

variable "repo_url" {
  description = "Git URL of the application repo to deploy."
  type        = string
  default     = "https://github.com/PsyVita/RapidAmente-TelemeTuna.git"
}


# --- Backups: daily standard-tier EBS snapshots + Recycle Bin ---------------
# Change any of these and `terraform apply` — it updates the policy in place
# (NO terraform destroy; the volume and instance are never touched).

variable "snapshot_cron" {
  description = "When to snapshot the Postgres volume (DLM cron, UTC). Default: 17:00 UTC = 00:00 Asia/Bangkok (daily midnight Thailand time)."
  type        = string
  default     = "cron(0 17 ? * * *)"
}

variable "standard_retain_count" {
  description = "How many of the most recent standard-tier snapshots to keep before deletion (then Recycle Bin)."
  type        = number
  default     = 30
}

variable "recycle_bin_retention_days" {
  description = "Days a deleted snapshot stays recoverable in the AWS Recycle Bin."
  type        = number
  default     = 7
}


# --- App credentials (non-secret: usernames / db / email) -------------------
# These become SSM parameters and are written into the instance .env at boot,
# so the app no longer depends on .env.example in production.

variable "postgres_user" {
  description = "Postgres username."
  type        = string
  default     = "user"
}

variable "postgres_db" {
  description = "Postgres database name."
  type        = string
  default     = "telemetry"
}

variable "grafana_admin_user" {
  description = "Grafana admin username."
  type        = string
  default     = "user"
}

variable "pgadmin_email" {
  description = "pgAdmin login email."
  type        = string
  default     = "admin@admin.com"
}

# --- App credentials (secret: passwords) ------------------------------------

variable "postgres_password" {
  description = "Postgres password (set in terraform.tfvars; never committed)"
  type        = string
  sensitive   = true
}

variable "grafana_admin_password" {
  description = "Grafana admin password (set in terraform.tfvars; never committed)"
  type        = string
  sensitive   = true
}

variable "pgadmin_password" {
  description = "pgAdmin password (set in terraform.tfvars; never committed)"
  type        = string
  sensitive   = true
}