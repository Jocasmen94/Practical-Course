# Demo ECS Fargate: Frontend + Backend con OIDC

App fullstack (React + Node.js) desplegada en AWS ECS Fargate, con infraestructura en Terraform y CI/CD en GitHub Actions autenticado por **OIDC** (sin access keys estáticas).

Repo: `Jocasmen94/Practical-Course` — este demo vive en la carpeta `demo-ecs-fargate/`.

---

## 1. Qué hace esta demo

- **Frontend**: React compilado a estáticos, servido por Nginx. Container en ECS Fargate.
- **Backend**: API Node.js/Express con `/health`, `/api/hello`, `/api/users`. Container en ECS Fargate.
- **ALB**: un solo Load Balancer público, enruta por path — `/*` va al frontend, `/api/*` va al backend.
- **Terraform**: crea toda la infraestructura (VPC, ALB, ECS, ECR, IAM, OIDC provider).
- **GitHub Actions**: en cada push a `main`, corre `terraform apply`, construye las imágenes Docker, las sube a ECR y fuerza el redeploy del servicio ECS — todo autenticado por OIDC, sin guardar credenciales AWS en GitHub.

---

## 2. Diagrama de arquitectura

```
                                   GitHub Actions (OIDC)
                                   ┌─────────────────────────────────┐
                                   │ 1. assume role via              │
                                   │    token.actions.githubusercontent.com
                                   │ 2. terraform apply              │
                                   │ 3. docker build + push -> ECR   │
                                   │ 4. ecs update-service            │
                                   └───────────────┬──────────────────┘
                                                    │ sts:AssumeRoleWithWebIdentity
                                                    ▼
                                   ┌─────────────────────────────────┐
                                   │   IAM Role: github-actions-deploy│
                                   │   trust: repo=Jocasmen94/Practical-Course
                                   │          branch=main             │
                                   └───────────────┬──────────────────┘
                                                    │ usa credenciales STS temporales
                                                    ▼
┌──────────────────────────────────── AWS Account ─────────────────────────────────────────┐
│                                                                                            │
│   ┌──────────────┐        ┌──────────────────────────────────────────────────┐          │
│   │  ECR (2 repos)│◄───push─│ frontend image / backend image                  │          │
│   │ frontend      │        └──────────────────────────────────────────────────┘          │
│   │ backend       │                                                                       │
│   └──────┬────────┘                                                                       │
│          │ pull (execution role)                                                          │
│          ▼                                                                                │
│   ┌───────────────────────────────── VPC 10.0.0.0/16 ─────────────────────────────────┐  │
│   │                                                                                     │  │
│   │   Internet                                                                         │  │
│   │      │                                                                             │  │
│   │      ▼                                                                             │  │
│   │  ┌─────────────────┐   Subnets públicas (10.0.1.0/24, 10.0.2.0/24)                │  │
│   │  │  Internet GW    │   ┌───────────────┐        ┌───────────────┐                 │  │
│   │  └───────┬─────────┘   │  ALB (públco) │        │  NAT Gateway   │                 │  │
│   │          │             │  listener :80 │        └───────┬───────┘                 │  │
│   │          └────────────►│               │                │                          │  │
│   │                        └───────┬───────┘                │ (egress internet         │  │
│   │                                │                         │  para tasks privadas)    │  │
│   │              ┌─────────────────┼─────────────────┐       │                          │  │
│   │              │ path "/*"       │ path "/api/*"    │       │                          │  │
│   │              ▼                 ▼                  │       │                          │  │
│   │      ┌──────────────┐  ┌──────────────┐            │       │                          │  │
│   │      │ TargetGroup  │  │ TargetGroup  │            │       │                          │  │
│   │      │ frontend :80 │  │ backend :8080│            │       │                          │  │
│   │      └──────┬───────┘  └──────┬───────┘            │       │                          │  │
│   │              │                 │                    │       │                          │  │
│   │   Subnets privadas (10.0.10.0/24, 10.0.11.0/24) ◄───┴───────┘                          │  │
│   │              ▼                 ▼                                                        │  │
│   │      ┌──────────────┐  ┌──────────────┐                                                │  │
│   │      │ ECS Fargate  │  │ ECS Fargate  │      SG ecs-tasks: solo permite tráfico         │  │
│   │      │ task frontend│  │ task backend │      entrante desde SG del ALB                  │  │
│   │      │ (nginx)      │  │ (node/express)│                                                │  │
│   │      └──────┬───────┘  └──────┬───────┘                                                │  │
│   │              │                 │                                                        │  │
│   │              ▼                 ▼                                                        │  │
│   │      CloudWatch Logs    CloudWatch Logs                                                 │  │
│   │      /ecs/*-frontend    /ecs/*-backend                                                  │  │
│   │                                                                                          │  │
│   └──────────────────────────────────────────────────────────────────────────────────────┘  │
│                                                                                               │
│   IAM roles usados por las tasks:                                                            │
│    - ecs-task-execution (pull ECR, escribir logs)                                            │
│    - ecs-task (permisos del código de la app en runtime)                                     │
│                                                                                               │
└───────────────────────────────────────────────────────────────────────────────────────────────┘
```

Flujo de una request de usuario:
1. Usuario pega `http://<alb-dns>` en el navegador.
2. ALB recibe en el listener `:80`, evalúa reglas de path.
3. Si es `/*` → forward a target group `frontend` → task ECS con Nginx sirviendo el build de React.
4. El frontend, desde el browser, llama a `${ALB_DNS}/api/hello` y `/api/users`.
5. ALB ve el path `/api/*` → forward a target group `backend` → task ECS con Express.
6. Backend responde JSON, frontend lo renderiza.

---

## 3. Internet Gateway vs NAT Gateway (por qué se usan los dos)

Resuelven cosas distintas, no son intercambiables:

- **Internet Gateway (IGW)**: da ruta bidireccional a subnets con IP pública. Solo lo usan las subnets **públicas** — ahí vive el ALB, que necesita ser alcanzable desde internet.
- **NAT Gateway**: da salida a internet a subnets **privadas** (sin IP pública), pero nadie de afuera puede entrar por ahí. Las tasks ECS viven en subnets privadas y necesitan salir a internet para pull de imágenes de ECR, llamadas a APIs externas, etc. Sin NAT, la task no tiene ruta de salida y falla al iniciar.

Por qué las tasks no están directo en la subnet pública con el IGW: seguridad — así no tienen IP pública ni son alcanzables directo desde internet, solo vía el ALB. Es el patrón estándar de AWS (defense in depth).

Alternativa para bajar costo en esta demo (el NAT Gateway es el recurso más caro, ~$32/mes): mover las tasks a subnets públicas con `assign_public_ip = true` y quitar el NAT. Menos seguro (el Security Group sigue protegiendo, pero la task queda con IP pública), aceptable para una demo corta, no recomendado para producción.

---

## 4. Estructura del repo

```
demo-ecs-fargate/
├── backend/            # Node.js + Express, Dockerfile
├── frontend/           # React + Nginx, Dockerfile
├── terraform/          # toda la infraestructura AWS
│   ├── main.tf          # provider + backend state (local por defecto)
│   ├── variables.tf
│   ├── vpc.tf           # VPC, subnets, NAT, IGW, route tables
│   ├── ecr.tf           # 2 repos ECR + lifecycle policy
│   ├── iam.tf           # roles de las tasks ECS
│   ├── oidc.tf          # OIDC provider de GitHub + role que asume Actions
│   ├── alb.tf           # ALB, target groups, listener, path rules
│   ├── ecs.tf           # cluster, task definitions, services
│   └── outputs.tf
├── .github/workflows/deploy.yml   # pipeline CI/CD con OIDC
└── README.md
```

---

## 5. Por qué OIDC en vez de AWS_ACCESS_KEY_ID / SECRET

- Credenciales de corta duración (STS), no secrets estáticos guardados en GitHub.
- El trust policy del IAM role (`oidc.tf`) solo permite `sts:AssumeRoleWithWebIdentity` desde el repo y branch exactos: `repo:Jocasmen94/Practical-Course:ref:refs/heads/main`. Si alguien copia el workflow a otro repo, no puede asumir el role.
- Revocable sin rotar nada: basta borrar el role o el OIDC provider en IAM.
- El `aws configure` que ya corriste sirve solo para el `terraform apply` **local** inicial (bootstrap, un solo apply). El workflow de CI nunca usa esas keys — usa el role vía OIDC.

---

## 6. Comandos paso a paso

### 5.1 Prerrequisitos

```bash
# Verificar CLI instaladas
aws --version
terraform -version
docker --version
gh --version   # opcional, para crear el secret desde terminal

# Confirmar identidad/cuenta AWS activa (la misma que usó `aws configure`)
aws sts get-caller-identity
```

### 5.2 Bootstrap de infraestructura (una sola vez, local)

```bash
cd demo-ecs-fargate/terraform

terraform init
terraform fmt -check
terraform validate
terraform plan -out=tfplan
terraform apply tfplan
```

Esto crea: VPC, ALB, ECS cluster + servicios (con imagen placeholder `latest`, aún no existe en ECR hasta el primer push del pipeline), ECR repos, IAM roles, OIDC provider + role de GitHub Actions.

> Nota: en el primer `apply`, los servicios ECS quedarán con tasks fallando (no hay imagen `latest` en ECR todavía). Eso se resuelve solo, en el primer run del workflow de GitHub Actions que sí construye y sube las imágenes.

### 5.3 Copiar el ARN del role de GitHub Actions

```bash
terraform output -raw github_actions_role_arn
```

Copia el valor, algo como:
```
arn:aws:iam::123456789012:role/boxful-demo-github-actions-deploy
```

### 5.4 Crear el secret en GitHub

Opción A — desde la web: **Settings → Secrets and variables → Actions → New repository secret**
```
Name:  AWS_ROLE_ARN
Value: <arn copiado en 5.3>
```

Opción B — con `gh` CLI:
```bash
gh secret set AWS_ROLE_ARN --repo Jocasmen94/Practical-Course --body "arn:aws:iam::123456789012:role/boxful-demo-github-actions-deploy"
```

No se necesita ningún otro secret (ni access keys).

### 5.5 Push del código al repo

```bash
# Desde la raíz de Practical-Course (aún no es repo git)
cd /Users/itboxful/Documents/Practical-Course
git init
git remote add origin https://github.com/Jocasmen94/Practical-Course.git
git add demo-ecs-fargate
git commit -m "Add ECS Fargate demo (frontend+backend, terraform, OIDC CI/CD)"
git branch -M main
git push -u origin main
```

Ese push dispara `.github/workflows/deploy.yml`, que:
1. Asume el role via OIDC.
2. Corre `terraform plan` (en PR) o `terraform apply` (en push a `main`).
3. Build + push de las imágenes `frontend` y `backend` a ECR (tags `latest` y `$GITHUB_SHA`).
4. `aws ecs update-service --force-new-deployment` por cada servicio.
5. `aws ecs wait services-stable` — el job no termina "success" hasta que las tasks nuevas estén healthy.

### 5.6 Verificar el deploy

```bash
# Ver estado del pipeline
gh run list --repo Jocasmen94/Practical-Course --limit 5
gh run watch --repo Jocasmen94/Practical-Course

# Ver la URL pública
cd demo-ecs-fargate/terraform
terraform output frontend_url

# Abrir en navegador o probar con curl
curl -s "$(terraform output -raw frontend_url)/health"
curl -s "$(terraform output -raw backend_url)/hello"
```

### 5.7 Debug rápido si algo falla

```bash
# Servicios y tasks
aws ecs describe-services --cluster boxful-demo --services boxful-demo-frontend boxful-demo-backend \
  --query 'services[].{name:serviceName,running:runningCount,desired:desiredCount,events:events[0:3]}'

# Logs filtrados de un servicio (evitar leer logs completos)
aws logs tail /ecs/boxful-demo-backend --since 10m | grep -E "ERROR|FATAL|panic|exception"
```

### 5.8 Cleanup (destruir todo)

```bash
cd demo-ecs-fargate/terraform
terraform destroy
```

Esto borra ALB, ECS, VPC/NAT, ECR (con las imágenes dentro), IAM roles y el OIDC provider. Confirmar antes de correrlo — es irreversible.

---

## 7. Nota de permisos (demo vs producción)

Para que el job de `terraform apply` en CI pueda crear VPC/ALB/IAM/ECS/ECR, el role de GitHub Actions (`oidc.tf`) tiene adjuntas `PowerUserAccess` + `IAMFullAccess`. Es intencional para simplificar la demo.

En un entorno real: separar en dos roles — uno para `terraform plan/apply` con policies scoped por servicio (vpc, alb, ecs, ecr, iam solo sobre los roles específicos), y otro (el que ya está definido en `aws_iam_role_policy.github_actions_deploy`, con permisos mínimos de ECR push/pull + ECS update-service + PassRole limitado) exclusivo para build & deploy sin terraform.

---

## 8. Costos estimados (us-east-1, desired_count=1 por servicio)

| Recurso | Costo aprox/mes |
|---|---|
| ALB | ~$16 |
| NAT Gateway | ~$32 |
| Fargate (2 tasks × 0.25 vCPU × 0.5GB) | ~$15 |
| **Total** | **~$63** |

Para bajar costo en la demo: eliminar el NAT Gateway y correr las tasks en subnets públicas con `assign_public_ip = true` (menos seguro, aceptable solo para demo corta).

---

## 9. Puntos clave para explicar en entrevista

- **Seguridad**: tasks en subnets privadas, ALB en públicas; security groups restrictivos (solo ALB → tasks); IAM least-privilege en los roles de las tasks; ECR con scanning; OIDC en vez de credenciales estáticas.
- **Escalabilidad**: Fargate serverless, sin gestión de servidores; multi-AZ; path-based routing en un solo ALB para dos servicios.
- **CI/CD**: un solo workflow con jobs secuenciales (`terraform` → `build-and-deploy` en matrix), gated por `terraform apply` exitoso, con `ecs wait services-stable` como health gate.
- **Costos**: lifecycle policy en ECR, Fargate Spot como capacity provider secundario.
- **IaC**: todo el estado de la infra vive en Terraform, reproducible con `terraform apply`, destruible con `terraform destroy`.
