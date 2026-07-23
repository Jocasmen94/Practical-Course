# OIDC provider de GitHub Actions - permite a los workflows asumir un role
# sin guardar AWS_ACCESS_KEY_ID/SECRET como secrets en GitHub.
resource "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"

  client_id_list = [
    "sts.amazonaws.com"
  ]

  # AWS valida el issuer de GitHub via IAMTrustStore desde 2023 y no usa este
  # campo, pero la API lo sigue devolviendo con un valor propio - se ignora
  # para no generar diff en cada plan.
  thumbprint_list = []

  lifecycle {
    ignore_changes = [thumbprint_list]
  }
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
          "token.actions.githubusercontent.com:aud"        = "sts.amazonaws.com"
          "token.actions.githubusercontent.com:repository" = var.github_repo
          "token.actions.githubusercontent.com:ref"        = "refs/heads/${var.github_branch}"
        }
        # AWS exige una condicion sobre "sub" (o job_workflow_ref) ademas de las
        # de arriba. Esta cuenta/repo tiene activado el hardening de GitHub que
        # agrega IDs inmutables al claim sub (repo:owner@ownerId/repo@repoId:...),
        # por eso el wildcard en el owner/repo - las condiciones StringEquals de
        # arriba (repository, ref) son las que realmente acotan el acceso.
        StringLike = {
          "token.actions.githubusercontent.com:sub" = "repo:*/*:ref:refs/heads/${var.github_branch}"
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

# El secret AWS_ROLE_ARN se crea una sola vez con un apply LOCAL (requiere
# GITHUB_TOKEN via `export GITHUB_TOKEN=$(gh auth token)`), usando el resource
# github_actions_secret del provider "github" (ver README seccion 6.2-6.3).
# No se gestiona desde aqui porque CI (GitHub Actions) no tiene un token con
# permiso para administrar secrets del propio repo - el token automatico
# ${{ secrets.GITHUB_TOKEN }} no alcanza para esa API. Si el role cambia de
# ARN, hay que volver a correr ese apply local una vez.
