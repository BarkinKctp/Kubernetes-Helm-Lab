output "cluster_name" { value = module.eks.cluster_name }
output "ecr_url" { value = aws_ecr_repository.app.repository_url }
output "gha_role_arn" { value = aws_iam_role.github_actions.arn }
output "account_id" { value = data.aws_caller_identity.current.account_id }
output "region" { value = var.region }
output "github_org" { value = var.github_org }
output "github_repo" { value = var.github_repo }
