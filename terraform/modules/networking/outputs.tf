output "vpc_id" {
  description = "ID da VPC"
  value       = aws_vpc.main.id
}

output "public_subnet_ids" {
  description = "IDs das subnets publicas"
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "IDs das subnets privadas"
  value       = aws_subnet.private[*].id
}

output "eks_nodes_sg_id" {
  description = "ID do security group dos EKS nodes"
  value       = aws_security_group.eks_nodes.id
}

output "rds_sg_id" {
  description = "ID do security group do RDS"
  value       = aws_security_group.rds.id
}

output "redis_sg_id" {
  description = "ID do security group do Redis"
  value       = aws_security_group.redis.id
}
