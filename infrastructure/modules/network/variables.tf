variable "project" {
  description = "Project name, used for naming/tagging."
  type        = string
}

variable "environment" {
  description = "Environment name (prod, dev)."
  type        = string
}

variable "admin_cidr" {
  description = "CIDR allowed to reach Grafana (3001) and MQTT (1884)."
  type        = string
}
