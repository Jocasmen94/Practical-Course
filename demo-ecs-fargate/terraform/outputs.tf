output "alb_dns_name" {
  description = "DNS del Application Load Balancer"
  value       = aws_lb.main.dns_name
}

output "frontend_url" {
  value = "http://${aws_lb.main.dns_name}"
}

output "backend_url" {
  value = "http://${aws_lb.main.dns_name}/api"
}

output "ecr_frontend_url" {
  value = aws_ecr_repository.frontend.repository_url
}

output "ecr_backend_url" {
  value = aws_ecr_repository.backend.repository_url
}

output "ecs_cluster_name" {
  value = aws_ecs_cluster.main.name
}

output "github_actions_role_arn" {
  description = "ARN a copiar en el secret AWS_ROLE_ARN de GitHub"
  value       = aws_iam_role.github_actions.arn
}
