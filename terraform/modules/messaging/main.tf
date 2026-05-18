############################
# SQS Queue
############################
resource "aws_sqs_queue" "main" {
  name                       = var.queue_name
  visibility_timeout_seconds = var.visibility_timeout
  message_retention_seconds  = var.message_retention

  tags = merge(var.tags, {
    Name = var.queue_name
  })
}
