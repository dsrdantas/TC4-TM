output "repository_urls" {
  description = "URLs dos repositorios ECR"
  value       = { for name, repo in aws_ecr_repository.services : name => repo.repository_url }
}

output "registry_id" {
  description = "ID do registry ECR"
  value       = values(aws_ecr_repository.services)[0].registry_id
}
