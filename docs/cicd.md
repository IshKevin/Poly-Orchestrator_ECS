# CI/CD Pipeline — Jenkins on AWS ECS

## Overview

The ShopNow CI/CD pipeline uses **Jenkins** to automate building, testing, pushing images to ECR, and deploying to ECS Fargate on every code push.

```
Developer pushes code
        │
        ▼
   Jenkins (EC2)
        │
  ┌─────┴──────┐
  │  Parallel  │
  ▼            ▼
Test         Test
Backend    Frontend
  │            │
  └─────┬──────┘
        ▼
  Build Docker Images
  (frontend + backend)
        │
        ▼
  Push to ECR
  (:<build_number> + :latest)
        │
        ▼
  Deploy Backend to ECS
  (aws ecs update-service + wait)
        │
        ▼
  Deploy Frontend to ECS
  (aws ecs update-service + wait)
        │
        ▼
  Cleanup workspace + prune images
```

Backend deploys before frontend to ensure the API is stable before the UI rolls out.

---

## Pipeline Stages

| Stage | What happens |
|---|---|
| **Checkout** | Clones the repository |
| **Test (parallel)** | Runs `pytest` for backend, `npm test` for frontend |
| **Build** | Resolves ECR URLs via `aws sts`, builds both Docker images tagged with `BUILD_NUMBER` and `latest` |
| **Push** | Authenticates Docker with ECR and pushes both tags for both images |
| **Deploy: Backend** | Triggers `aws ecs update-service --force-new-deployment` and waits for stability |
| **Deploy: Frontend** | Same as above for the frontend service |
| **Post** | Prunes dangling Docker images, cleans Jenkins workspace |

---

## Option A — Jenkins on AWS EC2 (Production)

### 1. Enable Jenkins in Terraform

In `terraform/terraform.tfvars`:

```hcl
jenkins_enabled       = true
jenkins_instance_type = "t3.medium"
jenkins_allowed_cidr  = ["YOUR_IP/32"]   # Replace with your public IP
jenkins_key_name      = "my-key-pair"    # Optional — for SSH access
```

### 2. Apply

```bash
cd terraform
terraform apply -auto-approve
terraform output jenkins_url
# http://<public-ip>:8080
```

Jenkins starts automatically via Docker on the EC2 instance. Allow **2–3 minutes** for Docker to pull the Jenkins image on first boot.

### 3. Retrieve the initial admin password

SSH into the instance (if `jenkins_key_name` is set):

```bash
ssh -i ~/.ssh/my-key-pair.pem ubuntu@<public-ip>

# Wait for Jenkins container to start, then:
sudo docker exec jenkins cat /var/jenkins_home/secrets/initialAdminPassword
```

Or retrieve it from the instance console output in the AWS EC2 console.

### 4. First-run configuration

1. Open `http://<public-ip>:8080` in your browser
2. Enter the initial admin password
3. Install **suggested plugins** (includes Git, Pipeline, Credentials)
4. Create an admin user

### 5. Create the pipeline job

1. **New Item** → enter `shopnow-deploy` → select **Pipeline** → OK
2. Under **Pipeline** → **Definition**: choose `Pipeline script from SCM`
3. SCM: `Git` → Repository URL: your repo URL
4. Script Path: `Jenkinsfile`
5. Save

The Jenkins EC2 instance uses an **IAM instance profile** — no AWS credentials need to be stored in Jenkins. The role has permission to:
- Push/pull ECR images (`shopnow-dev-frontend`, `shopnow-dev-backend`)
- Call `ecs:UpdateService` on `shopnow-dev-cluster`
- Call `sts:GetCallerIdentity` (to resolve the account ID)
- Write CloudWatch Logs

---

## Option B — Jenkins Locally with Docker (Development)

Useful for testing pipeline changes before pushing.

### 1. Build and start

```bash
# Set AWS credentials (the container reads these from the environment)
export AWS_ACCESS_KEY_ID=...
export AWS_SECRET_ACCESS_KEY=...
export AWS_DEFAULT_REGION=us-east-1

cd jenkins
docker compose up --build -d
```

Jenkins UI: http://localhost:8080

### 2. Initial admin password

```bash
docker exec shopnow-jenkins \
    cat /var/jenkins_home/secrets/initialAdminPassword
```

### 3. Stop

```bash
docker compose down        # keeps jenkins_home volume
docker compose down -v     # also removes volume (full reset)
```

---

## Triggering a Pipeline Run

**Manual:** Click **Build Now** in the Jenkins UI.

**Automatic via webhook** (recommended):

1. In Jenkins: **Manage Jenkins → Configure System → GitHub** → add your GitHub credentials
2. In your GitHub repo: **Settings → Webhooks → Add webhook**
   - Payload URL: `http://<jenkins-ip>:8080/github-webhook/`
   - Content type: `application/json`
   - Trigger: `Just the push event`

Every push to the configured branch now triggers a build automatically.

---

## Environment Variables in the Pipeline

| Variable | Default | Description |
|---|---|---|
| `AWS_REGION` | `us-east-1` | AWS region for ECR and ECS |
| `PROJECT_NAME` | `shopnow` | Matches the Terraform `project_name` |
| `ENV_NAME` | `dev` | Matches the Terraform `environment` |
| `ECS_CLUSTER` | derived | `${PROJECT_NAME}-${ENV_NAME}-cluster` |
| `IMAGE_TAG` | `${BUILD_NUMBER}` | Used to tag images for traceability |

To deploy to a different environment, override `ENV_NAME` in the Jenkins job configuration or parameterise the pipeline with `parameters { string(...) }`.

---

## Rollback

To roll back to the previous image:

```bash
# Get the previous task definition revision
aws ecs describe-services \
    --cluster shopnow-dev-cluster \
    --services shopnow-dev-backend \
    --query 'services[0].deployments'

# Update service to a specific task definition revision
aws ecs update-service \
    --cluster shopnow-dev-cluster \
    --service shopnow-dev-backend \
    --task-definition shopnow-dev-backend:PREVIOUS_REVISION
```

The deployment circuit breaker in the ECS service configuration also automatically rolls back if the new tasks fail their health checks.
