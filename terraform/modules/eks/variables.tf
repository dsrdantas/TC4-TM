variable "project_name" {
  description = "Nome do projeto"
  type        = string
}

variable "cluster_version" {
  description = "Versao do Kubernetes"
  type        = string
  default     = "1.31"
}

variable "subnet_ids" {
  description = "IDs das subnets para o cluster"
  type        = list(string)
}

variable "security_group_id" {
  description = "ID do security group para os nodes"
  type        = string
}

variable "lab_role_arn" {
  description = "ARN da LabRole (AWS Academy)"
  type        = string
}

variable "node_instance_types" {
  description = "Tipos de instancia para os nodes"
  type        = list(string)
  default     = ["t3.medium"]
}

variable "node_desired_size" {
  description = "Numero desejado de nodes"
  type        = number
  default     = 3
}

variable "node_min_size" {
  description = "Numero minimo de nodes"
  type        = number
  default     = 1
}

variable "node_max_size" {
  description = "Numero maximo de nodes"
  type        = number
  default     = 4
}

variable "tags" {
  description = "Tags adicionais"
  type        = map(string)
  default     = {}
}
