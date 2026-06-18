variable "project" {
  description = "Project name, used in the SSM parameter path."
  type        = string
}

variable "environment" {
  description = "Environment name, used in the SSM parameter path."
  type        = string
}

variable "postgres_password" {
  description = "Postgres password."
  type        = string
  sensitive   = true
}

variable "grafana_admin_password" {
  description = "Grafana admin password."
  type        = string
  sensitive   = true
}

variable "pgadmin_password" {
  description = "pgAdmin password."
  type        = string
  sensitive   = true
}
