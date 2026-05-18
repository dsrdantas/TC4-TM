terraform {
  backend "s3" {
    bucket         = "tc4-tm"
    key            = "infra/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "tc4-terraform-lock"
    encrypt        = true
  }
}
