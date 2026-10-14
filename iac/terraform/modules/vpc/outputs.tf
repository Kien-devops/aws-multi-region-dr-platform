output "vpc_id" { value = aws_vpc.this.id }
output "public_subnet_ids" { value = [for s in aws_subnet.public : s.id] }
output "private_subnet_ids" { value = [for s in aws_subnet.private : s.id] }
output "fsx_security_group_id" { value = aws_security_group.fsx.id }
output "nat_gateway_id" { value = aws_nat_gateway.this.id }
output "private_route_table_id" { value = aws_route_table.private.id }
