variable "project_name" {
  description = "Nome do projeto"
  type        = string
}

variable "queue_name" {
  description = "Nome da fila SQS"
  type        = string
  default     = "togglemaster-queue"
}

variable "visibility_timeout" {
  description = "Timeout de visibilidade da mensagem (segundos)"
  type        = number
  default     = 30
}

variable "message_retention" {
  description = "Retencao da mensagem (segundos)"
  type        = number
  default     = 86400
}

variable "tags" {
  description = "Tags adicionais"
  type        = map(string)
  default     = {}
}
