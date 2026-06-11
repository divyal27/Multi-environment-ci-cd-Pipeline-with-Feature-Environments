#!/usr/bin/env bash
set -euo pipefail

# Manual destroy for a given PR environment
# Usage: ./scripts/destroy-env.sh <pr-number>

PR_NUMBER="${1:?Usage: $0 <pr-number>}"
WORKSPACE="pr-${PR_NUMBER}"
TF_DIR="infrastructure"

echo "=== Destroying ephemeral environment: ${WORKSPACE} ==="

cd "$(dirname "$0")/../${TF_DIR}"

terraform init -backend-config="bucket=ephemeral-env-tfstate"

if ! terraform workspace select "${WORKSPACE}" 2>/dev/null; then
  echo "Workspace ${WORKSPACE} does not exist. Nothing to destroy."
  exit 0
fi

terraform destroy -auto-approve \
  -var="app_image=placeholder" \
  -var="dns_zone_name=app.dev" \
  -var="pr_number=${PR_NUMBER}"

terraform workspace select default
terraform workspace delete "${WORKSPACE}"

echo "=== Environment ${WORKSPACE} destroyed successfully ==="
