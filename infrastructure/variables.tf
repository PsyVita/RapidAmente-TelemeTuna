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
  description = "Size (GB) of the dedicated Postgres data disk."
  type        = number
  default     = 20
}

variable "repo_url" {
  description = "Git URL of the application repo to deploy."
  type        = string
  default     = "https://github.com/PsyVita/RapidAmente-TelemeTuna.git"
}


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

variable "cli_profile" {
  description = "Local AWS CLI/SSO profile name used in the SSM helper output. Developer-specific; override in your gitignored terraform.tfvars."
  type        = string
  default     = "tuna"
}