variable "repository_names" {
  description = "Nomes dos repositorios ECR"
  type        = list(string)
  default = [
    "auth-service",
    "flag-service",
    "targeting-service",
    "evaluation-service",
    "analytics-service"
  ]
}

variable "tags" {
  description = "Tags adicionais"
  type        = map(string)
  default     = {}
}
