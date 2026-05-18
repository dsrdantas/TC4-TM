output "queue_url" {
  description = "URL da fila SQS"
  value       = aws_sqs_queue.main.url
}

output "queue_arn" {
  description = "ARN da fila SQS"
  value       = aws_sqs_queue.main.arn
}

output "queue_name" {
  description = "Nome da fila SQS"
  value       = aws_sqs_queue.main.name
}
