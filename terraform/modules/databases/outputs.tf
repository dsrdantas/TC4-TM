output "auth_db_endpoint" {
  description = "Endpoint do RDS Auth DB"
  value       = aws_db_instance.auth.endpoint
}

output "auth_db_address" {
  description = "Endereco do RDS Auth DB"
  value       = aws_db_instance.auth.address
}

output "flag_db_endpoint" {
  description = "Endpoint do RDS Flag DB"
  value       = aws_db_instance.flag.endpoint
}

output "flag_db_address" {
  description = "Endereco do RDS Flag DB"
  value       = aws_db_instance.flag.address
}

output "targeting_db_endpoint" {
  description = "Endpoint do RDS Targeting DB"
  value       = aws_db_instance.targeting.endpoint
}

output "targeting_db_address" {
  description = "Endereco do RDS Targeting DB"
  value       = aws_db_instance.targeting.address
}

output "redis_endpoint" {
  description = "Endpoint do ElastiCache Redis"
  value       = aws_elasticache_cluster.redis.cache_nodes[0].address
}

output "redis_port" {
  description = "Porta do ElastiCache Redis"
  value       = aws_elasticache_cluster.redis.cache_nodes[0].port
}

output "dynamodb_table_name" {
  description = "Nome da tabela DynamoDB"
  value       = aws_dynamodb_table.analytics.name
}

output "dynamodb_table_arn" {
  description = "ARN da tabela DynamoDB"
  value       = aws_dynamodb_table.analytics.arn
}
