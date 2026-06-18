variable "project" {
  description = "Project name, used for naming."
  type        = string
}

variable "environment" {
  description = "Environment name, used for naming."
  type        = string
}

variable "aws_region" {
  description = "Region (scopes the kms:Decrypt-via-SSM condition)."
  type        = string
}

variable "secret_arns" {
  description = "ARNs of the SSM parameters the instance may read."
  type        = list(string)
}
