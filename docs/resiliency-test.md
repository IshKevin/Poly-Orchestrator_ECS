# Resiliency Testing — ECS Self-Healing Demo

This document demonstrates that ECS Fargate automatically detects and replaces unhealthy containers, keeping the application available throughout.

---

## Prerequisites

- Deployed infrastructure (see [deployment.md](deployment.md))
- AWS CLI configured
- Two terminal windows open

```bash
CLUSTER="shopnow-dev-cluster"
SERVICE="shopnow-dev-backend"
ALB=$(aws cloudformation describe-stacks 2>/dev/null || terraform -chdir=../terraform output -raw alb_dns_name 2>/dev/null)
```

---

## Test 1 — Manual Task Termination

### Step 1: Verify baseline

```bash
# Application is serving traffic
curl -s http://${ALB}/api/products | python3 -m json.tool

# Note the running task count (expect 2)
aws ecs describe-services \
  --cluster $CLUSTER \
  --services $SERVICE \
  --query 'services[0].{running:runningCount,desired:desiredCount}'
```

Expected:
```json
{ "running": 2, "desired": 2 }
```

### Step 2: List running tasks

```bash
aws ecs list-tasks \
  --cluster $CLUSTER \
  --service-name $SERVICE \
  --desired-status RUNNING \
  --query 'taskArns'
```

### Step 3: Stop one task

Copy a task ARN from the output above and stop it:

```bash
TASK_ARN="arn:aws:ecs:us-east-1:ACCOUNT_ID:task/shopnow-dev-cluster/XXXXXXXXXXXX"

aws ecs stop-task \
  --cluster $CLUSTER \
  --task $TASK_ARN \
  --reason "Resiliency test — manual stop"
```

### Step 4: Watch ECS recover (in a second terminal)

```bash
# Poll every 5 seconds — watch running count drop then recover
watch -n 5 "aws ecs describe-services \
  --cluster $CLUSTER \
  --services $SERVICE \
  --query 'services[0].{running:runningCount,desired:desiredCount,pending:pendingCount}'"
```

**Expected sequence**:
1. `running: 1, desired: 2, pending: 0` (task stopped)
2. `running: 1, desired: 2, pending: 1` (ECS scheduling replacement)
3. `running: 2, desired: 2, pending: 0` (recovered — typically within 60–90 s)

### Step 5: Verify continuous availability

Run this in parallel with Step 3–4:

```bash
while true; do
  STATUS=$(curl -s -o /dev/null -w "%{http_code}" http://${ALB}/api/health)
  echo "$(date '+%H:%M:%S')  HTTP $STATUS"
  sleep 2
done
```

The ALB health check removes the stopped task from the target group before stopping routes to it, so in most cases **no 5xx errors are returned** to clients.

---

## Test 2 — Stop Both Backend Tasks Simultaneously

This is a harder test: both tasks are removed at once.

```bash
# Get all running task ARNs
TASKS=$(aws ecs list-tasks \
  --cluster $CLUSTER \
  --service-name $SERVICE \
  --desired-status RUNNING \
  --query 'taskArns[]' \
  --output text)

# Stop all tasks
for TASK in $TASKS; do
  echo "Stopping $TASK"
  aws ecs stop-task --cluster $CLUSTER --task $TASK --reason "Resiliency test"
done
```

**Expected**:
- The ALB returns 502/503 for ≈30–90 seconds while ECS provisions new tasks
- Once new tasks pass health checks (`/api/health`), ALB re-routes and responses resume
- Service recovers to `running: 2` without any manual intervention

---

## Test 3 — Deployment Circuit Breaker

Simulate a bad deployment by pushing a broken image tag.

```bash
# Register a broken task definition (image tag that doesn't exist)
aws ecs register-task-definition \
  --family shopnow-dev-backend \
  --cli-input-json file://../ecs/task-definitions/backend.json \
  --overrides '{"containerOverrides":[{"name":"backend","image":"shopnow-dev-backend:broken-tag-does-not-exist"}]}'

# Update service to use new (broken) revision
aws ecs update-service \
  --cluster $CLUSTER \
  --service $SERVICE \
  --task-definition shopnow-dev-backend   # latest revision
```

**Expected**:
- New tasks fail to start (image pull error)
- Circuit breaker detects ≥ 10 consecutive launch failures
- ECS automatically rolls back to the previous healthy task definition revision
- Running tasks from the previous revision remain serving traffic throughout

Check the circuit breaker event:
```bash
aws ecs describe-services \
  --cluster $CLUSTER \
  --services $SERVICE \
  --query 'services[0].deployments'
```

---

## Expected Outcomes Summary

| Test | Trigger | Recovery Time | Client Impact |
|------|---------|---------------|---------------|
| Stop 1 task | Manual | < 90 s | None (ALB drains task first) |
| Stop all tasks | Manual | 60–120 s | Brief 502s while tasks start |
| Bad image rollout | Deployment | < 5 min | None (old tasks kept running) |

---

## Screenshots to Capture

For your submission, capture the following:

1. **Before**: ECS console showing 2/2 running tasks
2. **During**: Running count = 1 (task stopped), pending = 1
3. **After**: Running count = 2 again (fully recovered)
4. **Logs**: CloudWatch log stream showing the new task starting up
5. **Traffic**: Terminal showing continuous `HTTP 200` responses during recovery
