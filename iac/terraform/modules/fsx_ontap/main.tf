locals {
  tags = merge(
    {
      "Name" = var.name
    },
    var.tags
  )
}

resource "aws_fsx_ontap_file_system" "this" {
  deployment_type                   = var.deployment_type
  storage_capacity                  = var.storage_capacity
  throughput_capacity               = var.throughput_capacity
  subnet_ids                        = var.subnet_ids
  preferred_subnet_id               = var.preferred_subnet_id != null ? var.preferred_subnet_id : var.subnet_ids[0]
  security_group_ids                = var.security_group_ids
  fsx_admin_password                = var.fsx_admin_password
  kms_key_id                        = var.kms_key_id
  weekly_maintenance_start_time     = var.weekly_maintenance_start_time
  daily_automatic_backup_start_time = var.daily_automatic_backup_start_time
  automatic_backup_retention_days   = var.automatic_backup_retention_days

  dynamic "disk_iops_configuration" {
    for_each = var.disk_iops_mode != null ? [1] : []
    content {
      mode = var.disk_iops_mode
      iops = var.disk_iops
    }
  }

  tags = local.tags

  lifecycle {
    ignore_changes = [
      fsx_admin_password,
      security_group_ids,
    ]
  }
}

resource "aws_fsx_ontap_storage_virtual_machine" "this" {
  file_system_id     = aws_fsx_ontap_file_system.this.id
  name               = var.svm_name
  svm_admin_password = var.svm_admin_password

  tags = merge(
    var.tags,
    {
      "Name" = var.svm_name
    }
  )

  lifecycle {
    ignore_changes = [
      svm_admin_password,
    ]
  }
}

resource "aws_fsx_ontap_volume" "this" {
  name                       = var.volume_name
  storage_virtual_machine_id = aws_fsx_ontap_storage_virtual_machine.this.id
  junction_path              = var.volume_junction_path
  size_in_megabytes          = var.volume_size_in_megabytes
  storage_efficiency_enabled = var.volume_storage_efficiency_enabled
  ontap_volume_type          = var.ontap_volume_type
  security_style             = var.volume_security_style
  snapshot_policy            = var.volume_snapshot_policy

  dynamic "tiering_policy" {
    for_each = var.tiering_policy_name != null ? [1] : []
    content {
      name           = var.tiering_policy_name
      cooling_period = var.tiering_policy_cooling_period
    }
  }

  tags = merge(
    var.tags,
    {
      "Name" = var.volume_name
    }
  )

  lifecycle {
    ignore_changes = [
      bypass_snaplock_enterprise_retention,
    ]
  }
}
