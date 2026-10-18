module "sg_fsx" {
  count  = var.create_fsx ? 1 : 0
  source = "../../modules/fsx_ontap"

  name                              = "dr-sg-fsx-ontap"
  deployment_type                   = "SINGLE_AZ_1"
  storage_capacity                  = 1024
  throughput_capacity               = 128
  subnet_ids                        = [module.sg_network[0].private_subnet_ids[1]]
  preferred_subnet_id               = module.sg_network[0].private_subnet_ids[1]
  security_group_ids                = [module.sg_network[0].fsx_security_group_id]
  fsx_admin_password                = var.fsx_admin_password
  weekly_maintenance_start_time     = "3:18:30"
  daily_automatic_backup_start_time = "15:30"
  automatic_backup_retention_days   = 1
  disk_iops_mode                    = "AUTOMATIC"

  svm_name           = "dr-sg-svm"
  svm_admin_password = var.fsx_admin_password

  volume_name                       = "drdata"
  volume_junction_path              = "/dr-data"
  volume_size_in_megabytes          = 10240
  volume_storage_efficiency_enabled = true
  ontap_volume_type                 = "RW"
  volume_security_style             = "UNIX"
  volume_snapshot_policy            = "default"
  tiering_policy_name               = "SNAPSHOT_ONLY"
  tiering_policy_cooling_period     = 31

  tags = {
    Name = "dr-sg-fsx-ontap"
  }
}

module "tokyo_fsx" {
  count     = var.create_fsx ? 1 : 0
  source    = "../../modules/fsx_ontap"
  providers = { aws = aws.tokyo }

  name                              = "dr-tokyo-fsx-ontap"
  deployment_type                   = "SINGLE_AZ_1"
  storage_capacity                  = 1024
  throughput_capacity               = 128
  subnet_ids                        = [module.tokyo_network[0].private_subnet_ids[0]]
  preferred_subnet_id               = module.tokyo_network[0].private_subnet_ids[0]
  security_group_ids                = [module.tokyo_network[0].fsx_security_group_id]
  fsx_admin_password                = var.fsx_admin_password
  weekly_maintenance_start_time     = "3:14:00"
  daily_automatic_backup_start_time = "19:00"
  automatic_backup_retention_days   = 1
  disk_iops_mode                    = "AUTOMATIC"

  svm_name           = "dr-tokyo-svm"
  svm_admin_password = var.fsx_admin_password

  volume_name                       = "dr_data_dr"
  volume_junction_path              = "/dr-data"
  volume_size_in_megabytes          = 10240
  volume_storage_efficiency_enabled = false
  ontap_volume_type                 = "DP"
  volume_security_style             = "UNIX"
  volume_snapshot_policy            = "none"
  tiering_policy_name               = "SNAPSHOT_ONLY"
  tiering_policy_cooling_period     = 2

  tags = {
    Name        = "dr-tokyo-fsx-ontap"
    Project     = local.project
    Environment = local.environment
  }
}
