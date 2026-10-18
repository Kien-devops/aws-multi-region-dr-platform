output "file_system_id" {
  description = "The ID of the FSx ONTAP file system"
  value       = aws_fsx_ontap_file_system.this.id
}

output "file_system_arn" {
  description = "The Amazon Resource Name of the file system"
  value       = aws_fsx_ontap_file_system.this.arn
}

output "endpoints" {
  description = "The endpoints of the FSx ONTAP file system"
  value       = aws_fsx_ontap_file_system.this.endpoints
}

output "management_ip" {
  description = "Management IP address of the FSx ONTAP file system"
  value       = try(tolist(tolist(tolist(aws_fsx_ontap_file_system.this.endpoints)[0].management)[0].ip_addresses)[0], null)
}

output "storage_virtual_machine_id" {
  description = "The ID of the SVM"
  value       = aws_fsx_ontap_storage_virtual_machine.this.id
}

output "storage_virtual_machine_arn" {
  description = "The ARN of the SVM"
  value       = aws_fsx_ontap_storage_virtual_machine.this.arn
}

output "svm_endpoints" {
  description = "The endpoints of the SVM (NFS, SMB, iSCSI, Management)"
  value       = aws_fsx_ontap_storage_virtual_machine.this.endpoints
}

output "volume_id" {
  description = "The ID of the ONTAP Volume"
  value       = aws_fsx_ontap_volume.this.id
}

output "volume_arn" {
  description = "The ARN of the ONTAP Volume"
  value       = aws_fsx_ontap_volume.this.arn
}
