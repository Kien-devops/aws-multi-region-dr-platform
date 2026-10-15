output "global_cluster_id" { value = aws_rds_global_cluster.this.id }
output "primary_cluster_id" { value = try(aws_rds_cluster.primary[0].id, null) }
output "secondary_cluster_id" { value = try(aws_rds_cluster.secondary[0].id, null) }
