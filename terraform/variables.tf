variable "aws_region" {
  description = "Regiao AWS"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Nome do projeto"
  type        = string
  default     = "togglemaster"
}

variable "lab_role_arn" {
  description = "ARN da LabRole (AWS Academy)"
  type        = string
}

variable "db_password" {
  description = "Senha do PostgreSQL"
  type        = string
  sensitive   = true
}

variable "tags" {
  description = "Tags globais para todos os recursos"
  type        = map(string)
  default = {
    Project     = "ToggleMaster"
    Environment = "production"
    ManagedBy   = "terraform"
    Phase       = "3"
  }
}
