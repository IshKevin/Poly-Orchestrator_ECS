#!/bin/bash
# ============================================================================
# ShopNow — AWS Manual Resource Cleanup Script
#
# Deletes every resource created by the manual setup guide, in the correct
# reverse-dependency order. Resources with async deletion (RDS, ElastiCache,
# NAT GW) are polled until gone before moving to dependents.
#
# Usage:
#   chmod +x scripts/cleanup-aws-resources.sh
#   ./scripts/cleanup-aws-resources.sh
#
# Requirements: AWS CLI v2 configured with admin credentials
# ============================================================================

set -uo pipefail

# ── Configuration ─────────────────────────────────────────────────────────────
REGION="eu-west-1"       # Change to match your region
PROJECT="shopnow"
ENV="dev"
PREFIX="${PROJECT}-${ENV}"

# ── Colour helpers ────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; NC='\033[0m'

log()     { echo -e "${BLUE}[INFO ]${NC} $1"; }
ok()      { echo -e "${GREEN}[ OK  ]${NC} $1"; }
warn()    { echo -e "${YELLOW}[WARN ]${NC} $1"; }
section() { echo -e "\n${CYAN}━━━ $1 ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"; }

# ── Safety confirmation ───────────────────────────────────────────────────────
echo -e "${RED}"
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║           SHOPNOW AWS RESOURCE CLEANUP                      ║"
echo "║                                                              ║"
echo "║  This script PERMANENTLY deletes all ShopNow resources       ║"
echo "║  in region: ${REGION}                                   ║"
echo "║                                                              ║"
echo "║  Prefix:  ${PREFIX}                                   ║"
echo "║  This CANNOT be undone. RDS data will be lost.              ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo -e "${NC}"
echo "Type the prefix '${PREFIX}' to confirm deletion:"
read -r CONFIRM
if [[ "$CONFIRM" != "${PREFIX}" ]]; then
    echo "Confirmation mismatch — aborting."
    exit 0
fi

# ── Verify AWS credentials ────────────────────────────────────────────────────
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text --region "$REGION" 2>/dev/null) || {
    echo "ERROR: AWS credentials not configured or expired. Run 'aws configure'."
    exit 1
}
log "Account: $ACCOUNT_ID | Region: $REGION | Prefix: $PREFIX"
echo ""

# ── Helper: delete a security group by name ───────────────────────────────────
delete_sg() {
    local name="$1"
    local sg_id
    sg_id=$(aws ec2 describe-security-groups \
        --filters "Name=group-name,Values=${name}" \
        --query 'SecurityGroups[0].GroupId' \
        --output text --region "$REGION" 2>/dev/null || echo "")
    if [[ -n "$sg_id" && "$sg_id" != "None" ]]; then
        aws ec2 delete-security-group --group-id "$sg_id" --region "$REGION" 2>/dev/null && ok "Deleted SG: $name ($sg_id)" || warn "Could not delete SG $name — may already be gone or still in use"
    else
        warn "SG not found: $name"
    fi
}

# ═════════════════════════════════════════════════════════════════════════════
# STEP 1 — ECS Services (scale to 0 first so tasks drain cleanly)
# ═════════════════════════════════════════════════════════════════════════════
section "1/13  ECS Services"

CLUSTER="${PREFIX}-cluster"

for svc in "${PREFIX}-frontend" "${PREFIX}-backend"; do
    if aws ecs describe-services --cluster "$CLUSTER" --services "$svc" \
        --query 'services[0].status' --output text --region "$REGION" 2>/dev/null | grep -q "ACTIVE"; then
        log "Scaling $svc to 0..."
        aws ecs update-service --cluster "$CLUSTER" --service "$svc" \
            --desired-count 0 --region "$REGION" > /dev/null 2>&1 || true
    fi
done

log "Waiting for tasks to drain (up to 90 seconds)..."
sleep 30

for svc in "${PREFIX}-frontend" "${PREFIX}-backend"; do
    aws ecs delete-service --cluster "$CLUSTER" --service "$svc" \
        --force --region "$REGION" > /dev/null 2>&1 \
        && ok "Deleted ECS service: $svc" || warn "Service not found or already gone: $svc"
done

# ═════════════════════════════════════════════════════════════════════════════
# STEP 2 — ECS Task Definitions (deregister all revisions)
# ═════════════════════════════════════════════════════════════════════════════
section "2/13  ECS Task Definitions"

for family in "${PREFIX}-frontend" "${PREFIX}-backend"; do
    ARNS=$(aws ecs list-task-definitions --family-prefix "$family" \
        --query 'taskDefinitionArns[]' --output text --region "$REGION" 2>/dev/null || echo "")
    if [[ -n "$ARNS" ]]; then
        for arn in $ARNS; do
            aws ecs deregister-task-definition --task-definition "$arn" \
                --region "$REGION" > /dev/null 2>&1 \
                && ok "Deregistered: $arn" || warn "Could not deregister: $arn"
        done
    else
        warn "No task definitions found for family: $family"
    fi
done

# ═════════════════════════════════════════════════════════════════════════════
# STEP 3 — ECS Cluster
# ═════════════════════════════════════════════════════════════════════════════
section "3/13  ECS Cluster"

aws ecs delete-cluster --cluster "$CLUSTER" --region "$REGION" > /dev/null 2>&1 \
    && ok "Deleted ECS cluster: $CLUSTER" || warn "Cluster not found: $CLUSTER"

# ═════════════════════════════════════════════════════════════════════════════
# STEP 4 — Application Load Balancer (listeners → ALB → target groups)
# ═════════════════════════════════════════════════════════════════════════════
section "4/13  ALB, Listeners & Target Groups"

ALB_ARN=$(aws elbv2 describe-load-balancers --names "${PREFIX}-alb" \
    --query 'LoadBalancers[0].LoadBalancerArn' --output text --region "$REGION" 2>/dev/null || echo "")

if [[ -n "$ALB_ARN" && "$ALB_ARN" != "None" ]]; then
    # Delete all listeners (and their rules) by deleting the listener itself
    LISTENER_ARNS=$(aws elbv2 describe-listeners --load-balancer-arn "$ALB_ARN" \
        --query 'Listeners[].ListenerArn' --output text --region "$REGION" 2>/dev/null || echo "")
    for larn in $LISTENER_ARNS; do
        aws elbv2 delete-listener --listener-arn "$larn" --region "$REGION" > /dev/null 2>&1 \
            && ok "Deleted listener: $larn" || warn "Listener already gone: $larn"
    done

    log "Deleting ALB: ${PREFIX}-alb ..."
    aws elbv2 delete-load-balancer --load-balancer-arn "$ALB_ARN" --region "$REGION" > /dev/null 2>&1
    log "Waiting for ALB to be fully deleted..."
    aws elbv2 wait load-balancers-deleted --load-balancer-arns "$ALB_ARN" --region "$REGION" 2>/dev/null || true
    ok "ALB deleted"
else
    warn "ALB not found: ${PREFIX}-alb"
fi

# Target groups must be deleted after the ALB is gone (ALB holds references)
for tg in "${PREFIX}-tg-frontend" "${PREFIX}-tg-backend"; do
    TG_ARN=$(aws elbv2 describe-target-groups --names "$tg" \
        --query 'TargetGroups[0].TargetGroupArn' --output text --region "$REGION" 2>/dev/null || echo "")
    if [[ -n "$TG_ARN" && "$TG_ARN" != "None" ]]; then
        aws elbv2 delete-target-group --target-group-arn "$TG_ARN" --region "$REGION" > /dev/null 2>&1 \
            && ok "Deleted target group: $tg" || warn "Could not delete TG: $tg"
    else
        warn "Target group not found: $tg"
    fi
done

# ═════════════════════════════════════════════════════════════════════════════
# STEP 5 — Cloud Map (Service Discovery)
# ═════════════════════════════════════════════════════════════════════════════
section "5/13  Cloud Map (Service Discovery)"

NS_ID=$(aws servicediscovery list-namespaces \
    --query "Namespaces[?Name=='${PROJECT}.local'].Id" \
    --output text --region "$REGION" 2>/dev/null || echo "")

if [[ -n "$NS_ID" && "$NS_ID" != "None" ]]; then
    SVC_IDS=$(aws servicediscovery list-services \
        --filters "Name=NAMESPACE_ID,Values=${NS_ID},Condition=EQ" \
        --query 'Services[].Id' --output text --region "$REGION" 2>/dev/null || echo "")

    for svc_id in $SVC_IDS; do
        # Deregister all instances before deleting service
        INST_IDS=$(aws servicediscovery list-instances --service-id "$svc_id" \
            --query 'Instances[].Id' --output text --region "$REGION" 2>/dev/null || echo "")
        for inst_id in $INST_IDS; do
            aws servicediscovery deregister-instance --service-id "$svc_id" \
                --instance-id "$inst_id" --region "$REGION" > /dev/null 2>&1 || true
        done
        aws servicediscovery delete-service --id "$svc_id" --region "$REGION" > /dev/null 2>&1 \
            && ok "Deleted Cloud Map service: $svc_id" || warn "Could not delete CM service: $svc_id"
    done

    aws servicediscovery delete-namespace --id "$NS_ID" --region "$REGION" > /dev/null 2>&1 \
        && ok "Deleted Cloud Map namespace: ${PROJECT}.local ($NS_ID)" || warn "Could not delete namespace"
else
    warn "Cloud Map namespace '${PROJECT}.local' not found"
fi

# ═════════════════════════════════════════════════════════════════════════════
# STEP 6 — ElastiCache Redis (async — waits until gone)
# ═════════════════════════════════════════════════════════════════════════════
section "6/13  ElastiCache Redis"

REDIS_ID="${PREFIX}-redis"

if aws elasticache describe-cache-clusters --cache-cluster-id "$REDIS_ID" \
    --region "$REGION" > /dev/null 2>&1; then
    log "Deleting ElastiCache cluster: $REDIS_ID ..."
    aws elasticache delete-cache-cluster \
        --cache-cluster-id "$REDIS_ID" --region "$REGION" > /dev/null 2>&1 || true

    log "Waiting for ElastiCache to delete (3-5 minutes) ..."
    until ! aws elasticache describe-cache-clusters --cache-cluster-id "$REDIS_ID" \
        --region "$REGION" > /dev/null 2>&1; do
        echo -n "."
        sleep 15
    done
    echo ""
    ok "ElastiCache cluster deleted"
else
    warn "ElastiCache cluster not found: $REDIS_ID"
fi

# Subnet group can only be deleted after the cluster is gone
aws elasticache delete-cache-subnet-group \
    --cache-subnet-group-name "${PREFIX}-redis-subnet-group" \
    --region "$REGION" > /dev/null 2>&1 \
    && ok "Deleted ElastiCache subnet group" || warn "ElastiCache subnet group not found or still in use"

# ═════════════════════════════════════════════════════════════════════════════
# STEP 7 — RDS PostgreSQL (async — waits until gone)
# ═════════════════════════════════════════════════════════════════════════════
section "7/13  RDS PostgreSQL"

RDS_ID="${PREFIX}-postgres"

if aws rds describe-db-instances --db-instance-identifier "$RDS_ID" \
    --region "$REGION" > /dev/null 2>&1; then
    log "Deleting RDS instance: $RDS_ID (no final snapshot) ..."
    aws rds delete-db-instance \
        --db-instance-identifier "$RDS_ID" \
        --skip-final-snapshot \
        --region "$REGION" > /dev/null 2>&1 || true

    log "Waiting for RDS to delete (5-10 minutes) ..."
    aws rds wait db-instance-deleted \
        --db-instance-identifier "$RDS_ID" \
        --region "$REGION" 2>/dev/null || true
    ok "RDS instance deleted"
else
    warn "RDS instance not found: $RDS_ID"
fi

aws rds delete-db-subnet-group \
    --db-subnet-group-name "${PREFIX}-db-subnet-group" \
    --region "$REGION" > /dev/null 2>&1 \
    && ok "Deleted RDS subnet group" || warn "RDS subnet group not found or still in use"

# ═════════════════════════════════════════════════════════════════════════════
# STEP 8 — ECR Repositories (force-delete removes all images first)
# ═════════════════════════════════════════════════════════════════════════════
section "8/13  ECR Repositories"

for repo in "${PREFIX}-frontend" "${PREFIX}-backend"; do
    aws ecr delete-repository --repository-name "$repo" --force \
        --region "$REGION" > /dev/null 2>&1 \
        && ok "Deleted ECR repo: $repo" || warn "ECR repo not found: $repo"
done

# ═════════════════════════════════════════════════════════════════════════════
# STEP 9 — CloudWatch Log Groups
# ═════════════════════════════════════════════════════════════════════════════
section "9/13  CloudWatch Log Groups"

for lg in "/ecs/${PREFIX}/frontend" "/ecs/${PREFIX}/backend"; do
    aws logs delete-log-group --log-group-name "$lg" --region "$REGION" > /dev/null 2>&1 \
        && ok "Deleted log group: $lg" || warn "Log group not found: $lg"
done

# ═════════════════════════════════════════════════════════════════════════════
# STEP 10 — IAM Roles
# ═════════════════════════════════════════════════════════════════════════════
section "10/13  IAM Roles"

# Task execution role
EXEC_ROLE="${PREFIX}-task-execution"
aws iam detach-role-policy --role-name "$EXEC_ROLE" \
    --policy-arn "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy" 2>/dev/null || true
aws iam delete-role --role-name "$EXEC_ROLE" 2>/dev/null \
    && ok "Deleted IAM role: $EXEC_ROLE" || warn "Role not found: $EXEC_ROLE"

# Task role (has inline policy)
TASK_ROLE="${PREFIX}-task"
aws iam delete-role-policy --role-name "$TASK_ROLE" \
    --policy-name "cloudwatch-logs" 2>/dev/null || true
aws iam delete-role --role-name "$TASK_ROLE" 2>/dev/null \
    && ok "Deleted IAM role: $TASK_ROLE" || warn "Role not found: $TASK_ROLE"

# Jenkins role + instance profile
JENKINS_ROLE="${PROJECT}-jenkins-role"
aws iam detach-role-policy --role-name "$JENKINS_ROLE" \
    --policy-arn "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryPowerUser" 2>/dev/null || true
aws iam detach-role-policy --role-name "$JENKINS_ROLE" \
    --policy-arn "arn:aws:iam::aws:policy/AmazonECS_FullAccess" 2>/dev/null || true
aws iam remove-role-from-instance-profile \
    --instance-profile-name "$JENKINS_ROLE" \
    --role-name "$JENKINS_ROLE" 2>/dev/null || true
aws iam delete-instance-profile --instance-profile-name "$JENKINS_ROLE" 2>/dev/null || true
aws iam delete-role --role-name "$JENKINS_ROLE" 2>/dev/null \
    && ok "Deleted IAM role: $JENKINS_ROLE" || warn "Role not found: $JENKINS_ROLE"

# ═════════════════════════════════════════════════════════════════════════════
# STEP 11 — Jenkins EC2 Instance & Key Pair
# ═════════════════════════════════════════════════════════════════════════════
section "11/13  Jenkins EC2 & Key Pair"

JENKINS_INSTANCE_ID=$(aws ec2 describe-instances \
    --filters "Name=tag:Name,Values=${PREFIX}-jenkins" \
              "Name=instance-state-name,Values=running,stopped,pending,stopping" \
    --query 'Reservations[0].Instances[0].InstanceId' \
    --output text --region "$REGION" 2>/dev/null || echo "")

if [[ -n "$JENKINS_INSTANCE_ID" && "$JENKINS_INSTANCE_ID" != "None" ]]; then
    log "Terminating Jenkins EC2: $JENKINS_INSTANCE_ID ..."
    aws ec2 terminate-instances --instance-ids "$JENKINS_INSTANCE_ID" \
        --region "$REGION" > /dev/null 2>&1
    log "Waiting for termination ..."
    aws ec2 wait instance-terminated --instance-ids "$JENKINS_INSTANCE_ID" \
        --region "$REGION" 2>/dev/null || true
    ok "Jenkins instance terminated"
else
    warn "Jenkins instance not found (tag: ${PREFIX}-jenkins)"
fi

aws ec2 delete-key-pair --key-name "${PROJECT}-jenkins-key" \
    --region "$REGION" > /dev/null 2>&1 \
    && ok "Deleted key pair: ${PROJECT}-jenkins-key" || warn "Key pair not found"

# ═════════════════════════════════════════════════════════════════════════════
# STEP 12 — Security Groups
# Must be deleted in dependency order: leaf groups first, then the ones they
# referenced as sources. Deleting in wrong order causes "dependency violation".
#
# Dependency chain (X references Y as source means delete X before Y):
#   rds-sg    → references backend-sg  → delete rds-sg first
#   redis-sg  → references backend-sg  → delete redis-sg first
#   backend-sg → references frontend-sg, alb-sg → delete backend-sg next
#   frontend-sg → references alb-sg → delete frontend-sg next
#   alb-sg    → not referenced by anyone → delete last
# ═════════════════════════════════════════════════════════════════════════════
section "12/13  Security Groups"

for sg_name in \
    "${PREFIX}-sg-rds" \
    "${PREFIX}-sg-redis" \
    "${PREFIX}-sg-jenkins" \
    "${PREFIX}-sg-backend" \
    "${PREFIX}-sg-frontend" \
    "${PREFIX}-sg-alb"; do
    delete_sg "$sg_name"
done

# ═════════════════════════════════════════════════════════════════════════════
# STEP 13 — VPC Resources (NAT GW → EIP → IGW → Route Tables → Subnets → VPC)
# ═════════════════════════════════════════════════════════════════════════════
section "13/13  VPC, Subnets, Gateways, Route Tables"

VPC_ID=$(aws ec2 describe-vpcs \
    --filters "Name=tag:Name,Values=${PREFIX}-vpc" \
    --query 'Vpcs[0].VpcId' \
    --output text --region "$REGION" 2>/dev/null || echo "")

if [[ -z "$VPC_ID" || "$VPC_ID" == "None" ]]; then
    warn "VPC not found: ${PREFIX}-vpc — skipping VPC cleanup"
else
    log "Found VPC: $VPC_ID"

    # ── NAT Gateway ──────────────────────────────────────────────────────────
    NAT_ID=$(aws ec2 describe-nat-gateways \
        --filter "Name=vpc-id,Values=${VPC_ID}" \
                 "Name=state,Values=available,pending,deleting" \
        --query 'NatGateways[0].NatGatewayId' \
        --output text --region "$REGION" 2>/dev/null || echo "")

    if [[ -n "$NAT_ID" && "$NAT_ID" != "None" ]]; then
        log "Deleting NAT Gateway: $NAT_ID ..."
        aws ec2 delete-nat-gateway --nat-gateway-id "$NAT_ID" \
            --region "$REGION" > /dev/null 2>&1 || true

        log "Waiting for NAT Gateway to delete (~1 minute) ..."
        until [[ "$(aws ec2 describe-nat-gateways \
                --nat-gateway-ids "$NAT_ID" \
                --query 'NatGateways[0].State' \
                --output text --region "$REGION" 2>/dev/null)" == "deleted" ]]; do
            echo -n "."
            sleep 10
        done
        echo ""
        ok "NAT Gateway deleted"
    else
        warn "NAT Gateway not found in VPC $VPC_ID"
    fi

    # ── Elastic IP ───────────────────────────────────────────────────────────
    EIP_ALLOC=$(aws ec2 describe-addresses \
        --filters "Name=tag:Name,Values=${PREFIX}-nat-eip" \
        --query 'Addresses[0].AllocationId' \
        --output text --region "$REGION" 2>/dev/null || echo "")

    if [[ -n "$EIP_ALLOC" && "$EIP_ALLOC" != "None" ]]; then
        aws ec2 release-address --allocation-id "$EIP_ALLOC" \
            --region "$REGION" > /dev/null 2>&1 \
            && ok "Released Elastic IP: $EIP_ALLOC" || warn "Could not release EIP: $EIP_ALLOC"
    else
        warn "Elastic IP not found (tag: ${PREFIX}-nat-eip)"
    fi

    # ── Internet Gateway (must detach before deleting) ────────────────────────
    IGW_ID=$(aws ec2 describe-internet-gateways \
        --filters "Name=attachment.vpc-id,Values=${VPC_ID}" \
        --query 'InternetGateways[0].InternetGatewayId' \
        --output text --region "$REGION" 2>/dev/null || echo "")

    if [[ -n "$IGW_ID" && "$IGW_ID" != "None" ]]; then
        aws ec2 detach-internet-gateway \
            --internet-gateway-id "$IGW_ID" --vpc-id "$VPC_ID" \
            --region "$REGION" > /dev/null 2>&1 || true
        aws ec2 delete-internet-gateway \
            --internet-gateway-id "$IGW_ID" \
            --region "$REGION" > /dev/null 2>&1 \
            && ok "Deleted Internet Gateway: $IGW_ID" || warn "Could not delete IGW: $IGW_ID"
    else
        warn "Internet Gateway not found for VPC $VPC_ID"
    fi

    # ── Route Tables (non-main only; main cannot be deleted manually) ─────────
    RT_IDS=$(aws ec2 describe-route-tables \
        --filters "Name=vpc-id,Values=${VPC_ID}" \
        --query 'RouteTables[?Associations[?!Main] || !Associations].RouteTableId' \
        --output text --region "$REGION" 2>/dev/null || echo "")

    for rt_id in $RT_IDS; do
        # Check if it is the main route table (skip if so)
        IS_MAIN=$(aws ec2 describe-route-tables --route-table-ids "$rt_id" \
            --query 'RouteTables[0].Associations[?Main==`true`].RouteTableAssociationId' \
            --output text --region "$REGION" 2>/dev/null || echo "")
        if [[ -n "$IS_MAIN" ]]; then
            warn "Skipping main route table: $rt_id"
            continue
        fi

        # Remove subnet associations before deleting
        ASSOC_IDS=$(aws ec2 describe-route-tables --route-table-ids "$rt_id" \
            --query 'RouteTables[0].Associations[?!Main].RouteTableAssociationId' \
            --output text --region "$REGION" 2>/dev/null || echo "")
        for assoc_id in $ASSOC_IDS; do
            aws ec2 disassociate-route-table --association-id "$assoc_id" \
                --region "$REGION" > /dev/null 2>&1 || true
        done

        aws ec2 delete-route-table --route-table-id "$rt_id" \
            --region "$REGION" > /dev/null 2>&1 \
            && ok "Deleted route table: $rt_id" || warn "Could not delete route table: $rt_id"
    done

    # ── Subnets ───────────────────────────────────────────────────────────────
    SUBNET_IDS=$(aws ec2 describe-subnets \
        --filters "Name=vpc-id,Values=${VPC_ID}" \
        --query 'Subnets[].SubnetId' \
        --output text --region "$REGION" 2>/dev/null || echo "")

    for subnet_id in $SUBNET_IDS; do
        aws ec2 delete-subnet --subnet-id "$subnet_id" \
            --region "$REGION" > /dev/null 2>&1 \
            && ok "Deleted subnet: $subnet_id" || warn "Could not delete subnet: $subnet_id"
    done

    # ── VPC ───────────────────────────────────────────────────────────────────
    aws ec2 delete-vpc --vpc-id "$VPC_ID" --region "$REGION" > /dev/null 2>&1 \
        && ok "Deleted VPC: $VPC_ID" || warn "Could not delete VPC — may still have dependent resources"
fi

# ═════════════════════════════════════════════════════════════════════════════
# Done
# ═════════════════════════════════════════════════════════════════════════════
echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}  Cleanup complete. All ShopNow resources have been removed.${NC}"
echo -e "${GREEN}  Verify in the AWS console that nothing remains.${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
