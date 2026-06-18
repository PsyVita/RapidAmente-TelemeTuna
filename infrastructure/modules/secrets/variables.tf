variable "project" {
  description = "Project name, used in the SSM parameter path."
  type        = string
}

variable "environment" {
  description = "Environment name, used in the SSM parameter path."
  type        = string
}

variable "postgres_user" {
  description = "Postgres username."
  type        = string
}

variable "postgres_db" {
  description = "Postgres database name."
  type        = string
}

variable "grafana_admin_user" {
  description = "Grafana admin username."
  type        = string
}

variable "pgadmin_email" {
  description = "pgAdmin login email."
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
