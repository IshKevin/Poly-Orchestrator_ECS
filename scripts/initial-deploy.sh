#!/bin/bash
# Initial manual deploy — run this once from your local machine.
# After this, Jenkins handles all subsequent deploys on code push.
set -e

AWS_REGION="eu-west-1"
PROJECT_NAME="shopnow"
ENV_NAME="dev"

echo "==> [1/4] Provisioning infrastructure with Terraform"
cd "$(dirname "$0")/../terraform"
terraform init
terraform apply -auto-approve

echo ""
echo "==> [2/4] Resolving ECR URLs"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
ECR_BASE="${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
ECR_FRONTEND="${ECR_BASE}/${PROJECT_NAME}-${ENV_NAME}-frontend"
ECR_BACKEND="${ECR_BASE}/${PROJECT_NAME}-${ENV_NAME}-backend"

echo "    Frontend: ${ECR_FRONTEND}"
echo "    Backend:  ${ECR_BACKEND}"

echo ""
echo "==> [3/4] Building and pushing Docker images"
aws ecr get-login-password --region "${AWS_REGION}" \
    | docker login --username AWS --password-stdin "${ECR_BASE}"

cd "$(dirname "$0")/.."

docker build -t "${ECR_FRONTEND}:latest" ./app/frontend
docker push "${ECR_FRONTEND}:latest"

docker build -t "${ECR_BACKEND}:latest" ./app/backend
docker push "${ECR_BACKEND}:latest"

echo ""
echo "==> [4/4] Forcing ECS to pull the new images"
ECS_CLUSTER="${PROJECT_NAME}-${ENV_NAME}-cluster"

aws ecs update-service \
    --cluster  "${ECS_CLUSTER}" \
    --service  "${PROJECT_NAME}-${ENV_NAME}-backend" \
    --force-new-deployment \
    --region   "${AWS_REGION}" > /dev/null

aws ecs update-service \
    --cluster  "${ECS_CLUSTER}" \
    --service  "${PROJECT_NAME}-${ENV_NAME}-frontend" \
    --force-new-deployment \
    --region   "${AWS_REGION}" > /dev/null

echo ""
echo "==> Waiting for services to stabilise (this takes ~2 min)..."
aws ecs wait services-stable \
    --cluster  "${ECS_CLUSTER}" \
    --services "${PROJECT_NAME}-${ENV_NAME}-backend" "${PROJECT_NAME}-${ENV_NAME}-frontend" \
    --region   "${AWS_REGION}"

ALB_URL=$(terraform -chdir="$(dirname "$0")/../terraform" output -raw alb_url)
JENKINS_URL=$(terraform -chdir="$(dirname "$0")/../terraform" output -raw jenkins_url)

echo ""
echo "==> Deploy complete!"
echo "    App:     ${ALB_URL}"
echo "    Jenkins: ${JENKINS_URL}"
echo ""
echo "Next: open Jenkins, install plugins, add a Pipeline job pointing at"
echo "      this repo with Jenkinsfile as the pipeline script."
