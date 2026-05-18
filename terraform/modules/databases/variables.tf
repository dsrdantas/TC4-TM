variable "project_name" {
  description = "Nome do projeto"
  type        = string
}

variable "vpc_id" {
  description = "ID da VPC"
  type        = string
}

variable "private_subnet_ids" {
  description = "IDs das subnets privadas"
  type        = list(string)
}

variable "rds_sg_id" {
  description = "ID do security group do RDS"
  type        = string
}

variable "redis_sg_id" {
  description = "ID do security group do Redis"
  type        = string
}

variable "db_username" {
  description = "Usuario do PostgreSQL"
  type        = string
  default     = "tm_user"
}

variable "db_password" {
  description = "Senha do PostgreSQL"
  type        = string
  sensitive   = true
}

variable "db_instance_class" {
  description = "Classe da instancia RDS"
  type        = string
  default     = "db.t3.micro"
}

variable "redis_node_type" {
  description = "Tipo do node ElastiCache"
  type        = string
  default     = "cache.t3.micro"
}

variable "tags" {
  description = "Tags adicionais"
  type        = map(string)
  default     = {}
}
