output "mount_target_ids" {
  value = aws_efs_mount_target.efs.*.id
}

output "volume_id" {
  value = aws_efs_file_system.efs.id
}
