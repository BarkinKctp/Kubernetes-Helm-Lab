# Terraform backend configuration
# After running bootstrap/main.tf, copy the outputs below

terraform {
  backend "s3" {
    bucket         = "terraform-state-ACCOUNT_ID-eu-west-1" # From bootstrap output: bucket_name
    key            = "eks/terraform.tfstate"
    region         = "eu-west-1"
    dynamodb_table = "terraform-locks" # From bootstrap output: dynamodb_table
    encrypt        = true
  }
}
