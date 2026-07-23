# OIDC provider de GitHub Actions - permite a los workflows asumir un role
# sin guardar AWS_ACCESS_KEY_ID/SECRET como secrets en GitHub.
resource "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"

  client_id_list = [
    "sts.amazonaws.com"
  ]

  # Thumbprint gestionado por AWS desde 2023 (root CA de GitHub), se deja vacio
  # para que AWS lo resuelva automaticamente; si el provider se rechaza, usar:
  # thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]
  thumbprint_list = []
}

resource "aws_iam_role" "github_actions" {
  name = "${var.project_name}-github-actions-deploy"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = aws_iam_openid_connect_provider.github.arn
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
        }
        StringLike = {
          "token.actions.githubusercontent.com:sub" = "repo:${var.github_repo}:ref:refs/heads/${var.github_branch}"
        }
      }
    }]
  })
}

# Permisos para que el workflow construya/despliegue (ECR, ECS, logs).
# Terraform apply desde CI requiere permisos amplios de los servicios que
# este demo gestiona (vpc, alb, ecs, ecr, iam, logs). Para produccion, dividir
# en policies mas finas por job (plan/apply vs build/deploy).
resource "aws_iam_role_policy" "github_actions_deploy" {
  name = "${var.project_name}-deploy-policy"
  role = aws_iam_role.github_actions.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "ECRAuth"
        Effect   = "Allow"
        Action   = ["ecr:GetAuthorizationToken"]
        Resource = "*"
      },
      {
        Sid    = "ECRPushPull"
        Effect = "Allow"
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:PutImage",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload"
        ]
        Resource = [
          aws_ecr_repository.frontend.arn,
          aws_ecr_repository.backend.arn
        ]
      },
      {
        Sid    = "ECSDeploy"
        Effect = "Allow"
        Action = [
          "ecs:UpdateService",
          "ecs:DescribeServices",
          "ecs:DescribeTaskDefinition",
          "ecs:RegisterTaskDefinition"
        ]
        Resource = "*"
      },
      {
        Sid    = "PassTaskRoles"
        Effect = "Allow"
        Action = "iam:PassRole"
        Resource = [
          aws_iam_role.ecs_task_execution.arn,
          aws_iam_role.ecs_task.arn
        ]
      },
      {
        Sid    = "TerraformState"
        Effect = "Allow"
        Action = [
          "ec2:Describe*",
          "elasticloadbalancing:Describe*",
          "logs:Describe*",
          "logs:List*",
          "ecs:Describe*",
          "ecs:List*",
          "ecr:Describe*"
        ]
        Resource = "*"
      }
    ]
  })
}

# El job de "terraform apply" en CI necesita permisos amplios (vpc, alb, iam,
# ecs, ecr, logs) para crear/actualizar toda la infra de este demo. Para no
# mantener una policy gigante a mano, se adjunta PowerUserAccess + IAMFullAccess
# SOLO para esta demo. En un entorno real: separar el job de terraform a un
# role con policies scoped por servicio, y dejar el role de arriba (deploy)
# solo con los permisos de build/push/deploy ya definidos.
resource "aws_iam_role_policy_attachment" "github_actions_poweruser" {
  role       = aws_iam_role.github_actions.name
  policy_arn = "arn:aws:iam::aws:policy/PowerUserAccess"
}

resource "aws_iam_role_policy_attachment" "github_actions_iam" {
  role       = aws_iam_role.github_actions.name
  policy_arn = "arn:aws:iam::aws:policy/IAMFullAccess"
}
