variable "project" {
  description = "Project name, used for naming/tagging."
  type        = string
}

variable "environment" {
  description = "Environment name."
  type        = string
}

variable "aws_region" {
  description = "Region (passed into the boot script template)."
  type        = string
}

variable "instance_type" {
  description = "EC2 instance size."
  type        = string
}

variable "root_volume_size" {
  description = "Size (GB) of the root/OS disk."
  type        = number
}

variable "data_volume_size" {
  description = "Size (GB) of the dedicated Postgres data disk."
  type        = number
}

variable "repo_url" {
  description = "Git URL of the application repo to deploy."
  type        = string
}

variable "subnet_id" {
  description = "Subnet to launch the instance in."
  type        = string
}

variable "subnet_az" {
  description = "Availability zone for the data volume (must match the subnet)."
  type        = string
}

variable "security_group_id" {
  description = "Security group to attach to the instance."
  type        = string
}

variable "instance_profile_name" {
  description = "IAM instance profile name to attach."
  type        = string
}
