output "bucket_name" {
  value       = aws_s3_bucket.terraform_state.id
  description = "S3 bucket name for Terraform state"
}

output "dynamodb_table" {
  value       = aws_dynamodb_table.terraform_locks.name
  description = "DynamoDB table name for state locking"
}

output "account_id" {
  value       = data.aws_caller_identity.current.account_id
  description = "AWS Account ID"
}

output "region" {
  value       = var.region
  description = "AWS region"
}
