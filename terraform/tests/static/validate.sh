#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TF_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
PASS=0
FAIL=0

pass() { echo "[PASS] $1"; PASS=$((PASS + 1)); }
fail() { echo "[FAIL] $1"; FAIL=$((FAIL + 1)); }

# Test 1: terraform fmt
if terraform -chdir="$TF_DIR" fmt -check -recursive > /dev/null 2>&1; then
  pass "Terraform formatting is correct"
else
  fail "Terraform formatting issues found — run 'terraform fmt -recursive'"
fi

# Test 2: terraform validate (requires init)
if terraform -chdir="$TF_DIR" validate > /dev/null 2>&1; then
  pass "Terraform configuration is valid"
else
  fail "Terraform validation failed"
fi

# Test 3: No hardcoded AWS account IDs
if grep -rn '346607799227\|[0-9]\{12\}' "$TF_DIR"/*.tf 2>/dev/null | grep -v 'backend.tf' | grep -v '.terraform' > /dev/null 2>&1; then
  fail "Hardcoded AWS account ID found in .tf files (excluding backend.tf)"
else
  pass "No hardcoded AWS account IDs in .tf files"
fi

# Test 4: All variables have descriptions
VARS_WITHOUT_DESC=$(grep -c 'variable "' "$TF_DIR/variables.tf" 2>/dev/null || echo 0)
VARS_WITH_DESC=$(grep -c 'description' "$TF_DIR/variables.tf" 2>/dev/null || echo 0)
if [ "$VARS_WITHOUT_DESC" -le "$VARS_WITH_DESC" ]; then
  pass "All variables have descriptions ($VARS_WITHOUT_DESC vars, $VARS_WITH_DESC descriptions)"
else
  fail "Some variables missing descriptions ($VARS_WITHOUT_DESC vars, $VARS_WITH_DESC descriptions)"
fi

# Test 5: All outputs have descriptions
if [ -f "$TF_DIR/outputs.tf" ]; then
  OUTS=$(grep -c 'output "' "$TF_DIR/outputs.tf" 2>/dev/null || echo 0)
  OUTS_DESC=$(grep -c 'description' "$TF_DIR/outputs.tf" 2>/dev/null || echo 0)
  if [ "$OUTS" -le "$OUTS_DESC" ]; then
    pass "All outputs have descriptions"
  else
    fail "Some outputs missing descriptions"
  fi
else
  fail "outputs.tf not found"
fi

# Test 6: .gitignore exists and covers basics
if [ -f "$TF_DIR/../.gitignore" ]; then
  if grep -q 'tfstate' "$TF_DIR/../.gitignore" && grep -q '.terraform' "$TF_DIR/../.gitignore"; then
    pass ".gitignore covers .tfstate and .terraform"
  else
    fail ".gitignore missing critical patterns"
  fi
else
  fail ".gitignore not found"
fi

# Test 7: YAML validation of examples
YAML_PASS=true
for f in "$TF_DIR"/examples/*.yaml; do
  if [ -f "$f" ]; then
    if kubectl apply --dry-run=client -f "$f" > /dev/null 2>&1; then
      pass "YAML valid: $(basename "$f")"
    else
      # kubectl dry-run requires a cluster; just check basic syntax
      if python3 -c "import yaml; yaml.safe_load(open('$f'))" 2>/dev/null; then
        pass "YAML syntax valid: $(basename "$f")"
      else
        fail "YAML invalid: $(basename "$f")"
        YAML_PASS=false
      fi
    fi
  fi
done

# Test 8: No TODO/FIXME in .tf files
if grep -rn 'TODO\|FIXME\|HACK\|XXX' "$TF_DIR"/*.tf 2>/dev/null | grep -v '.terraform' > /dev/null 2>&1; then
  fail "TODO/FIXME found in .tf files"
else
  pass "No TODO/FIXME in .tf files"
fi

# Test 9: README exists
if [ -f "$TF_DIR/README.md" ]; then
  pass "README.md exists"
else
  fail "README.md not found"
fi

# Test 10: Bootstrap directory exists
if [ -d "$TF_DIR/bootstrap" ] && [ -f "$TF_DIR/bootstrap/main.tf" ]; then
  pass "Bootstrap directory exists with main.tf"
else
  fail "Bootstrap directory missing or incomplete"
fi

echo ""
echo "================================"
echo "Static Tests: $PASS passed, $FAIL failed out of $((PASS + FAIL)) total"
echo "================================"

[ "$FAIL" -eq 0 ] && exit 0 || exit 1
