variable "name" {
  description = "Name tag for the FSx ONTAP file system"
  type        = string
}

variable "deployment_type" {
  description = "The deployment type of the FSx for ONTAP file system. Valid values: SINGLE_AZ_1, MULTI_AZ_1."
  type        = string
  default     = "SINGLE_AZ_1"
}

variable "storage_capacity" {
  description = "The storage capacity (in GiB) of the file system. Minimum 1024."
  type        = number
  default     = 1024
}

variable "throughput_capacity" {
  description = "The throughput capacity (in MBps) of the file system."
  type        = number
  default     = 128
}

variable "subnet_ids" {
  description = "List of subnet IDs for the file system."
  type        = list(string)
}

variable "preferred_subnet_id" {
  description = "The preferred subnet ID for the file system (required for Single-AZ and Multi-AZ)."
  type        = string
  default     = null
}

variable "security_group_ids" {
  description = "A list of security group IDs for the file system."
  type        = list(string)
}

variable "fsx_admin_password" {
  description = "The ONTAP administrative password for the fsxadmin user."
  type        = string
  default     = null
  sensitive   = true
}

variable "kms_key_id" {
  description = "ARN or ID of the AWS KMS key used to encrypt the file system's data."
  type        = string
  default     = null
}

variable "weekly_maintenance_start_time" {
  description = "The preferred start time to perform weekly maintenance, in d:HH:MM format."
  type        = string
  default     = null
}

variable "daily_automatic_backup_start_time" {
  description = "A recurring daily time, in HH:MM format, to initiate automatic daily backups."
  type        = string
  default     = null
}

variable "automatic_backup_retention_days" {
  description = "The number of days to retain automatic backups."
  type        = number
  default     = 1
}

variable "disk_iops_mode" {
  description = "The SSD IOPS mode for the file system. Valid values: AUTOMATIC, USER_PROVISIONED."
  type        = string
  default     = "AUTOMATIC"
}

variable "disk_iops" {
  description = "The total number of SSD IOPS provisioned for the file system (if USER_PROVISIONED)."
  type        = number
  default     = null
}

variable "svm_name" {
  description = "The name of the Storage Virtual Machine (SVM)."
  type        = string
}

variable "svm_admin_password" {
  description = "The password for the SVM administrator."
  type        = string
  default     = null
  sensitive   = true
}

variable "volume_name" {
  description = "The name of the ONTAP Volume."
  type        = string
}

variable "volume_junction_path" {
  description = "The location within the SVM namespace where the volume is mounted."
  type        = string
  default     = "/dr-data"
}

variable "volume_size_in_megabytes" {
  description = "The size of the volume, in megabytes."
  type        = number
  default     = 10240
}

variable "volume_storage_efficiency_enabled" {
  description = "Set to true to enable deduplication, compression, and compaction."
  type        = bool
  default     = true
}

variable "ontap_volume_type" {
  description = "The type of the volume. Valid values: RW, DP."
  type        = string
  default     = "RW"
}

variable "volume_security_style" {
  description = "The security style for the volume. Valid values: UNIX, NTFS, MIXED."
  type        = string
  default     = "UNIX"
}

variable "volume_snapshot_policy" {
  description = "The name of the snapshot policy."
  type        = string
  default     = "default"
}

variable "tiering_policy_name" {
  description = "The name of the volume's tiering policy. Valid values: SNAPSHOT_ONLY, AUTO, ALL, NONE."
  type        = string
  default     = "SNAPSHOT_ONLY"
}

variable "tiering_policy_cooling_period" {
  description = "The cooling period for the tiering policy, in days."
  type        = number
  default     = 31
}

variable "tags" {
  description = "A map of tags to assign to all resources."
  type        = map(string)
  default     = {}
}
