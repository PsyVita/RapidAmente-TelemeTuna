# Root module: wires the building blocks together.
# Dependency order is inferred automatically from the references below
# (secrets -> iam, network -> compute, iam -> compute).

module "network" {
  source      = "./modules/network"
  project     = var.project
  environment = var.environment
  admin_cidr  = var.admin_cidr
}

module "secrets" {
  source                 = "./modules/secrets"
  project                = var.project
  environment            = var.environment
  postgres_user          = var.postgres_user
  postgres_db            = var.postgres_db
  grafana_admin_user     = var.grafana_admin_user
  pgadmin_email          = var.pgadmin_email
  postgres_password      = var.postgres_password
  grafana_admin_password = var.grafana_admin_password
  pgadmin_password       = var.pgadmin_password
}

module "iam" {
  source      = "./modules/iam"
  project     = var.project
  environment = var.environment
  aws_region  = var.aws_region
  secret_arns = module.secrets.parameter_arns
}

module "compute" {
  source                = "./modules/compute"
  project               = var.project
  environment           = var.environment
  aws_region            = var.aws_region
  instance_type         = var.instance_type
  root_volume_size      = var.root_volume_size
  data_volume_size      = var.data_volume_size
  repo_url              = var.repo_url
  subnet_id             = module.network.subnet_id
  subnet_az             = module.network.subnet_az
  security_group_id     = module.network.security_group_id
  instance_profile_name = module.iam.instance_profile_name
}

# Daily standard-tier EBS snapshots of the Postgres data volume + a Recycle Bin
# recovery window. Targets the volume by its Backup=postgres tag, so it has no
# dependency on the compute module beyond that volume existing.
module "backup" {
  source                     = "./modules/backup"
  project                    = var.project
  environment                = var.environment
  snapshot_cron              = var.snapshot_cron
  standard_retain_count      = var.standard_retain_count
  recycle_bin_retention_days = var.recycle_bin_retention_days
}