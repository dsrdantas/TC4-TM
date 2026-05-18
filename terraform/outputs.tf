############################
# Networking
############################
output "vpc_id" {
  description = "ID da VPC"
  value       = module.networking.vpc_id
}

############################
# EKS
############################
output "eks_cluster_name" {
  description = "Nome do cluster EKS"
  value       = module.eks.cluster_name
}

output "eks_cluster_endpoint" {
  description = "Endpoint do cluster EKS"
  value       = module.eks.cluster_endpoint
}

############################
# Databases
############################
output "auth_db_endpoint" {
  description = "Endpoint do Auth DB"
  value       = module.databases.auth_db_endpoint
}

output "flag_db_endpoint" {
  description = "Endpoint do Flag DB"
  value       = module.databases.flag_db_endpoint
}

output "targeting_db_endpoint" {
  description = "Endpoint do Targeting DB"
  value       = module.databases.targeting_db_endpoint
}

output "redis_endpoint" {
  description = "Endpoint do Redis"
  value       = module.databases.redis_endpoint
}

output "dynamodb_table_name" {
  description = "Nome da tabela DynamoDB"
  value       = module.databases.dynamodb_table_name
}

############################
# Messaging
############################
output "sqs_queue_url" {
  description = "URL da fila SQS"
  value       = module.messaging.queue_url
}

############################
# ECR
############################
output "ecr_repository_urls" {
  description = "URLs dos repositorios ECR"
  value       = module.ecr.repository_urls
}
