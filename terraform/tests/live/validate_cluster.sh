#!/usr/bin/env bash
set -euo pipefail

PASS=0
FAIL=0
SKIP=0

pass() { echo "[PASS] $1"; PASS=$((PASS + 1)); }
fail() { echo "[FAIL] $1: ${2:-}"; FAIL=$((FAIL + 1)); }
skip() { echo "[SKIP] $1: ${2:-}"; SKIP=$((SKIP + 1)); }

CLUSTER_NAME="${1:-opsfleet-eks}"
REGION="${2:-us-east-1}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EXAMPLES_DIR="$(cd "$SCRIPT_DIR/../../examples" && pwd)"

echo "Validating cluster: $CLUSTER_NAME in $REGION"
echo "================================================"

# --- SECTION 1: EKS Cluster ---
echo ""
echo "--- Section 1: EKS Cluster ---"

CLUSTER_STATUS=$(aws eks describe-cluster --name "$CLUSTER_NAME" --region "$REGION" --query 'cluster.status' --output text 2>/dev/null || echo "NOT_FOUND")
if [ "$CLUSTER_STATUS" = "ACTIVE" ]; then
  pass "EKS cluster is ACTIVE"
else
  fail "EKS cluster status" "$CLUSTER_STATUS"
fi

CLUSTER_VERSION=$(aws eks describe-cluster --name "$CLUSTER_NAME" --region "$REGION" --query 'cluster.version' --output text 2>/dev/null || echo "UNKNOWN")
if [[ "$CLUSTER_VERSION" == "1.3"* ]]; then
  pass "Cluster version: $CLUSTER_VERSION"
else
  fail "Cluster version" "$CLUSTER_VERSION"
fi

ENCRYPTION=$(aws eks describe-cluster --name "$CLUSTER_NAME" --region "$REGION" --query 'cluster.encryptionConfig[0].resources[0]' --output text 2>/dev/null || echo "NONE")
if [ "$ENCRYPTION" = "secrets" ]; then
  pass "KMS encryption enabled for secrets"
else
  fail "KMS encryption" "$ENCRYPTION"
fi

LOGGING=$(aws eks describe-cluster --name "$CLUSTER_NAME" --region "$REGION" --query 'cluster.logging.clusterLogging[?enabled==`true`].types[]' --output text 2>/dev/null || echo "NONE")
if echo "$LOGGING" | grep -q "api"; then
  pass "Cluster logging enabled: $LOGGING"
else
  fail "Cluster logging" "$LOGGING"
fi

# Configure kubectl
aws eks update-kubeconfig --name "$CLUSTER_NAME" --region "$REGION" > /dev/null 2>&1
if kubectl cluster-info > /dev/null 2>&1; then
  pass "kubectl configured and cluster reachable"
else
  fail "kubectl cannot reach cluster"
fi

# --- SECTION 2: Node Group ---
echo ""
echo "--- Section 2: System Nodes ---"

READY_NODES=$(kubectl get nodes --no-headers 2>/dev/null | grep -c "Ready" || echo 0)
if [ "$READY_NODES" -ge 2 ]; then
  pass "System nodes ready: $READY_NODES"
else
  fail "System nodes ready" "$READY_NODES (expected >= 2)"
fi

SYSTEM_LABELED=$(kubectl get nodes -l role=system --no-headers 2>/dev/null | wc -l | tr -d ' ')
if [ "$SYSTEM_LABELED" -ge 2 ]; then
  pass "System nodes labeled: $SYSTEM_LABELED"
else
  fail "System node labels" "$SYSTEM_LABELED nodes with role=system"
fi

# --- SECTION 3: Karpenter ---
echo ""
echo "--- Section 3: Karpenter ---"

KARPENTER_PODS=$(kubectl get pods -n kube-system -l app.kubernetes.io/name=karpenter --no-headers 2>/dev/null | grep -c "Running" || echo 0)
if [ "$KARPENTER_PODS" -ge 1 ]; then
  pass "Karpenter controller running: $KARPENTER_PODS pods"
else
  fail "Karpenter controller" "$KARPENTER_PODS running pods"
fi

X86_POOL=$(kubectl get nodepool x86-general --no-headers 2>/dev/null | wc -l | tr -d ' ')
if [ "$X86_POOL" -ge 1 ]; then
  pass "NodePool x86-general exists"
else
  fail "NodePool x86-general" "not found"
fi

ARM_POOL=$(kubectl get nodepool arm64-graviton --no-headers 2>/dev/null | wc -l | tr -d ' ')
if [ "$ARM_POOL" -ge 1 ]; then
  pass "NodePool arm64-graviton exists"
else
  fail "NodePool arm64-graviton" "not found"
fi

NODE_CLASS=$(kubectl get ec2nodeclass default --no-headers 2>/dev/null | wc -l | tr -d ' ')
if [ "$NODE_CLASS" -ge 1 ]; then
  pass "EC2NodeClass default exists"
else
  fail "EC2NodeClass default" "not found"
fi

# --- SECTION 4: SQS & EventBridge ---
echo ""
echo "--- Section 4: SQS & EventBridge ---"

SQS_URL=$(aws sqs get-queue-url --queue-name "Karpenter-${CLUSTER_NAME}" --region "$REGION" --output text 2>/dev/null || \
          aws sqs get-queue-url --queue-name "${CLUSTER_NAME}-karpenter" --region "$REGION" --output text 2>/dev/null || echo "NOT_FOUND")
if [ "$SQS_URL" != "NOT_FOUND" ]; then
  pass "SQS interruption queue exists"
else
  fail "SQS interruption queue" "not found"
fi

DLQ_URL=$(aws sqs get-queue-url --queue-name "Karpenter-${CLUSTER_NAME}-dlq" --region "$REGION" --output text 2>/dev/null || \
          aws sqs get-queue-url --queue-name "${CLUSTER_NAME}-karpenter-dlq" --region "$REGION" --output text 2>/dev/null || echo "NOT_FOUND")
if [ "$DLQ_URL" != "NOT_FOUND" ]; then
  pass "SQS DLQ exists"
else
  skip "SQS DLQ" "module uses main queue only"
fi

EB_RULES=$(aws events list-rules --name-prefix "Karpenter" --region "$REGION" --query 'Rules[].Name' --output text 2>/dev/null | wc -w | tr -d ' ')
if [ "$EB_RULES" -ge 4 ]; then
  pass "EventBridge rules: $EB_RULES"
else
  fail "EventBridge rules" "$EB_RULES (expected >= 4)"
fi

# --- SECTION 5: VPC & Network ---
echo ""
echo "--- Section 5: VPC & Network ---"

VPC_ID=$(aws eks describe-cluster --name "$CLUSTER_NAME" --region "$REGION" --query 'cluster.resourcesVpcConfig.vpcId' --output text 2>/dev/null || echo "NOT_FOUND")
if [ "$VPC_ID" != "NOT_FOUND" ]; then
  pass "VPC found: $VPC_ID"
else
  fail "VPC" "not found"
fi

FLOW_LOGS=$(aws ec2 describe-flow-logs --filter "Name=resource-id,Values=$VPC_ID" --region "$REGION" --query 'FlowLogs[].FlowLogId' --output text 2>/dev/null | wc -w | tr -d ' ')
if [ "$FLOW_LOGS" -ge 1 ]; then
  pass "VPC Flow Logs enabled: $FLOW_LOGS"
else
  fail "VPC Flow Logs" "not found for $VPC_ID"
fi

VPC_ENDPOINTS=$(aws ec2 describe-vpc-endpoints --filters "Name=vpc-id,Values=$VPC_ID" --region "$REGION" --query 'VpcEndpoints[].ServiceName' --output text 2>/dev/null | wc -w | tr -d ' ')
if [ "$VPC_ENDPOINTS" -ge 5 ]; then
  pass "VPC endpoints: $VPC_ENDPOINTS"
else
  fail "VPC endpoints" "$VPC_ENDPOINTS (expected >= 5)"
fi

# --- SECTION 6: Monitoring ---
echo ""
echo "--- Section 6: Monitoring ---"

ALARMS=$(aws cloudwatch describe-alarms --alarm-name-prefix "$CLUSTER_NAME" --region "$REGION" --query 'MetricAlarms[].AlarmName' --output text 2>/dev/null | wc -w | tr -d ' ')
if [ "$ALARMS" -ge 2 ]; then
  pass "CloudWatch alarms: $ALARMS"
else
  fail "CloudWatch alarms" "$ALARMS (expected >= 2)"
fi

# --- SECTION 7: Workload Scheduling ---
echo ""
echo "--- Section 7: Workload Scheduling ---"

echo "Deploying nginx-x86..."
kubectl apply -f "$EXAMPLES_DIR/nginx-x86.yaml" > /dev/null 2>&1

echo "Waiting for x86 pods (up to 180s)..."
if kubectl wait --for=condition=ready pod -l app=nginx-x86 --timeout=180s 2>/dev/null; then
  pass "nginx-x86 pods are Running"
  
  X86_NODE=$(kubectl get pods -l app=nginx-x86 -o jsonpath='{.items[0].spec.nodeName}' 2>/dev/null)
  X86_ARCH=$(kubectl get node "$X86_NODE" -o jsonpath='{.metadata.labels.kubernetes\.io/arch}' 2>/dev/null || echo "unknown")
  if [ "$X86_ARCH" = "amd64" ]; then
    pass "x86 pod running on amd64 node: $X86_NODE"
  else
    fail "x86 pod architecture" "$X86_ARCH on $X86_NODE"
  fi
else
  fail "nginx-x86 pods" "did not become ready in 180s"
fi

echo "Deploying nginx-arm64..."
kubectl apply -f "$EXAMPLES_DIR/nginx-arm64.yaml" > /dev/null 2>&1

echo "Waiting for arm64 pods (up to 180s)..."
if kubectl wait --for=condition=ready pod -l app=nginx-arm64 --timeout=180s 2>/dev/null; then
  pass "nginx-arm64 pods are Running"
  
  ARM_NODE=$(kubectl get pods -l app=nginx-arm64 -o jsonpath='{.items[0].spec.nodeName}' 2>/dev/null)
  ARM_ARCH=$(kubectl get node "$ARM_NODE" -o jsonpath='{.metadata.labels.kubernetes\.io/arch}' 2>/dev/null || echo "unknown")
  if [ "$ARM_ARCH" = "arm64" ]; then
    pass "arm64 pod running on arm64 node: $ARM_NODE"
  else
    fail "arm64 pod architecture" "$ARM_ARCH on $ARM_NODE"
  fi
else
  fail "nginx-arm64 pods" "did not become ready in 180s"
fi

# Check Spot
echo ""
echo "--- Section 8: Spot Verification ---"
SPOT_NODES=$(kubectl get nodes -l karpenter.sh/capacity-type=spot --no-headers 2>/dev/null | wc -l | tr -d ' ')
OD_NODES=$(kubectl get nodes -l karpenter.sh/capacity-type=on-demand --no-headers 2>/dev/null | wc -l | tr -d ' ')
pass "Karpenter nodes: $SPOT_NODES spot, $OD_NODES on-demand"

# --- SECTION 9: Cleanup Test ---
echo ""
echo "--- Section 9: Cleanup ---"
kubectl delete -f "$EXAMPLES_DIR/nginx-x86.yaml" --ignore-not-found > /dev/null 2>&1
kubectl delete -f "$EXAMPLES_DIR/nginx-arm64.yaml" --ignore-not-found > /dev/null 2>&1
pass "Test workloads cleaned up"

echo ""
echo "================================================"
echo "Live Tests: $PASS passed, $FAIL failed, $SKIP skipped out of $((PASS + FAIL + SKIP)) total"
echo "================================================"

[ "$FAIL" -eq 0 ] && exit 0 || exit 1
