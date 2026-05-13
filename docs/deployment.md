# Deployment Guide

This guide walks through deploying ShopNow end-to-end: local testing, pushing images to ECR, and provisioning AWS infrastructure with Terraform.

---

## Prerequisites

| Tool | Minimum Version | Install |
|------|-----------------|---------|
| Docker + Docker Compose | 24+ / 2.24+ | https://docs.docker.com/get-docker/ |
| Terraform | 1.6+ | https://developer.hashicorp.com/terraform/install |
| AWS CLI | 2.15+ | https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html |
| Git | any | — |

Configure AWS CLI with a profile that has permissions for ECS, ECR, VPC, RDS, ElastiCache, ALB, IAM, CloudWatch, and Cloud Map:

```bash
aws configure
# or: export AWS_PROFILE=shopnow
```

---

## Phase 1 — Local Development

### 1.1 Start all services

```bash
cd app
docker compose up --build
```

Services:
| Service | Local URL |
|---------|-----------|
| Frontend | http://localhost:3000 |
| Backend API | http://localhost:5000 |
| PostgreSQL | localhost:5432 |
| Redis | localhost:6379 |

### 1.2 Verify health

```bash
curl http://localhost:5000/api/health
curl http://localhost:5000/api/products
curl http://localhost:3000/health
```

### 1.3 Tear down

```bash
docker compose down -v   # -v removes named volumes (wipes DB data)
```

---

## Phase 2 — Build and Push Images to ECR

### 2.1 Authenticate Docker with ECR

```bash
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
REGION=us-east-1

aws ecr get-login-password --region $REGION \
  | docker login --username AWS --password-stdin \
    ${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com
```

### 2.2 Build images

```bash
# From project root
docker build -t shopnow-frontend ./app/frontend
docker build -t shopnow-backend  ./app/backend
```

### 2.3 Tag and push

```bash
FRONTEND_REPO="${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com/shopnow-dev-frontend"
BACKEND_REPO="${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com/shopnow-dev-backend"

docker tag shopnow-frontend:latest ${FRONTEND_REPO}:latest
docker tag shopnow-backend:latest  ${BACKEND_REPO}:latest

docker push ${FRONTEND_REPO}:latest
docker push ${BACKEND_REPO}:latest
```

> **Note**: ECR repositories are created by Terraform in Phase 3. Run `terraform apply` first (without ECS services), push images, then apply again with ECS services.

---

## Phase 3 — Provision AWS Infrastructure

### 3.1 Configure variables

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars — at minimum set db_password
```

### 3.2 Initialise Terraform

```bash
terraform init
```

### 3.3 Plan

```bash
terraform plan -out=tfplan
```

Review the output. Expect ~35-40 resources.

### 3.4 Apply (two-step for ECR → images → ECS)

**Step A** — Create ECR repositories so images can be pushed before ECS deploys:

```bash
terraform apply -target=module.ecr -auto-approve
```

Push images (Phase 2 above), then:

**Step B** — Apply everything:

```bash
terraform apply -auto-approve
```

### 3.5 Verify outputs

```bash
terraform output alb_url
# http://shopnow-dev-alb-XXXXXXXXXXXX.us-east-1.elb.amazonaws.com
```

Open the URL in your browser — you should see the ShopNow storefront.

---

## Phase 4 — Verify Services

### Check ECS service status

```bash
CLUSTER=$(terraform output -raw ecs_cluster_name)

aws ecs list-services --cluster $CLUSTER
aws ecs describe-services \
  --cluster $CLUSTER \
  --services shopnow-dev-frontend shopnow-dev-backend \
  --query 'services[*].{name:serviceName,running:runningCount,desired:desiredCount,status:status}'
```

### Tail container logs

```bash
# Backend logs (last 50 lines, follow)
aws logs tail /ecs/shopnow-dev/backend --follow --since 5m

# Frontend logs
aws logs tail /ecs/shopnow-dev/frontend --follow --since 5m
```

### Test API via ALB

```bash
ALB=$(terraform output -raw alb_dns_name)

curl http://${ALB}/api/health
curl http://${ALB}/api/products | python3 -m json.tool
```

---

## Phase 5 — Updating a Service

When you push a new image and want to roll it out:

```bash
# Force new deployment (ECS pulls the :latest tag)
aws ecs update-service \
  --cluster shopnow-dev-cluster \
  --service shopnow-dev-backend \
  --force-new-deployment
```

Or update the task definition revision in Terraform and re-run `terraform apply`.

---

## Teardown

**Destroy all AWS resources** (incurs no further charges):

```bash
cd terraform
terraform destroy -auto-approve
```

> This deletes everything including the RDS database. In production set `skip_final_snapshot = false` in `rds.tf` to retain a snapshot.
