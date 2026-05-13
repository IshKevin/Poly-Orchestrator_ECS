# Architecture Overview — ShopNow on AWS ECS Fargate

## High-Level Diagram

```
Internet
   │
   ▼
Route 53 (optional)
   │
   ▼
Application Load Balancer  ←─── public subnets (10.0.1.0/24, 10.0.2.0/24)
   │                │
   │  /api/*        │  /*
   ▼                ▼
Backend Service   Frontend Service   ←─── private subnets (10.0.10.0/24, 10.0.20.0/24)
(Flask :5000)     (Node.js :3000)
   │
   ├──► RDS PostgreSQL  (private subnet, port 5432)
   └──► ElastiCache Redis  (private subnet, port 6379)

All private traffic leaves via NAT Gateway → Internet Gateway
```

---

## Tiers

### Tier 1 — Presentation (Frontend)
- **Runtime**: Node.js 20 on Alpine Linux
- **Framework**: Express.js — serves static HTML/JS and proxies `/api/*` to the backend
- **Container port**: 3000
- **DNS (service discovery)**: `frontend.shopnow.local`

### Tier 2 — Application (Backend)
- **Runtime**: Python 3.12 on Debian Slim
- **Framework**: Flask 3 + Gunicorn (2 workers)
- **Container port**: 5000
- **DNS (service discovery)**: `backend.shopnow.local`
- **Endpoints**:
  | Method | Path | Description |
  |--------|------|-------------|
  | GET | `/api/health` | Liveness + readiness probe |
  | GET | `/api/products` | List all products (PostgreSQL) |
  | GET | `/api/products/<id>` | Single product detail |
  | GET | `/api/cart/<session>` | Retrieve cart (Redis) |
  | POST | `/api/cart/<session>` | Add item to cart |
  | DELETE | `/api/cart/<session>` | Clear cart |

### Tier 3 — Data
| Service | AWS Managed | Port | Purpose |
|---------|-------------|------|---------|
| PostgreSQL 16 | RDS | 5432 | Product catalog, order history |
| Redis 7 | ElastiCache | 6379 | Session carts, caching |

---

## Networking

### VPC — `10.0.0.0/16`

| Subnet | CIDR | AZ | Type | Resources |
|--------|------|----|------|-----------|
| public-1 | 10.0.1.0/24 | us-east-1a | Public | ALB, NAT GW |
| public-2 | 10.0.2.0/24 | us-east-1b | Public | ALB |
| private-1 | 10.0.10.0/24 | us-east-1a | Private | ECS tasks, RDS, Redis |
| private-2 | 10.0.20.0/24 | us-east-1b | Private | ECS tasks, RDS (Multi-AZ standby) |

### Traffic Flow
1. User request → Route 53 → ALB (public subnet, port 80)
2. `/api/*` → backend target group → backend ECS tasks (private subnet, port 5000)
3. `/*` → frontend target group → frontend ECS tasks (private subnet, port 3000)
4. Frontend container makes server-side calls to `backend.shopnow.local:5000` via Cloud Map
5. Backend reads/writes PostgreSQL and Redis in private subnets
6. Containers pull images from ECR via NAT GW

### Security Groups
```
Internet → (80, 443) → ALB SG
ALB SG   → (3000)    → Frontend SG
ALB SG   → (5000)    → Backend SG
Frontend SG → (5000) → Backend SG
Backend SG  → (5432) → RDS SG
Backend SG  → (6379) → Redis SG
```

---

## ECS Architecture

### Cluster
- Name: `shopnow-dev-cluster`
- Capacity providers: FARGATE (base), FARGATE_SPOT (overflow)
- Container Insights: enabled

### Services
| Service | Tasks | CPU | Memory | Subnets |
|---------|-------|-----|--------|---------|
| frontend | 2 | 256 (0.25 vCPU) | 512 MiB | private |
| backend | 2 | 256 (0.25 vCPU) | 512 MiB | private |

### Deployment Strategy
- Rolling update: `minimumHealthyPercent = 100`, `maximumPercent = 200`
- Circuit breaker: enabled with automatic rollback on health-check failure

---

## Service Discovery

AWS Cloud Map private DNS namespace: `shopnow.local`

| Service | DNS Name | Port |
|---------|----------|------|
| frontend | `frontend.shopnow.local` | 3000 |
| backend | `backend.shopnow.local` | 5000 |

The frontend container uses the environment variable `BACKEND_URL=http://backend.shopnow.local:5000`
to reach the backend without hardcoded IPs.

---

## Container Images

Stored in Amazon ECR:

| Repository | Purpose |
|-----------|---------|
| `shopnow-dev-frontend` | Node.js frontend |
| `shopnow-dev-backend` | Python Flask backend |

Lifecycle policy: keep last 10 tagged images; remove untagged after 1 day.

---

## Infrastructure as Code

All AWS resources are managed with **Terraform ≥ 1.6**:

| Module | Contents |
|--------|----------|
| `modules/networking` | VPC, subnets, IGW, NAT GW, route tables |
| `modules/security` | ALB, frontend, backend, RDS, Redis security groups |
| `modules/ecr` | ECR repositories + lifecycle policies |
| `modules/alb` | ALB, target groups, listener rules |
| `modules/ecs` | Cluster, IAM, CloudWatch log groups, Cloud Map, task definitions, services |
| `modules/rds` | RDS PostgreSQL 16 |
| `modules/elasticache` | ElastiCache Redis 7 |
