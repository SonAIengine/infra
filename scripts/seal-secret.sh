#!/bin/bash
set -euo pipefail

# =============================================================================
# Secret Creation Helper
# Creates Kubernetes secrets from .env files or key-value pairs
# Usage:
#   ./seal-secret.sh <namespace> <secret-name> --from-env-file <path>
#   ./seal-secret.sh <namespace> <secret-name> --from-literal KEY=VALUE ...
# =============================================================================

if [ $# -lt 3 ]; then
  echo "Usage:"
  echo "  $0 <namespace> <secret-name> --from-env-file <path>"
  echo "  $0 <namespace> <secret-name> --from-literal KEY=VALUE [--from-literal KEY2=VALUE2 ...]"
  echo ""
  echo "Examples:"
  echo "  $0 dongtan dongtan-db-secret --from-env-file ./secrets/dongtan-db.env"
  echo "  $0 dongtan dongtan-app-secret --from-literal DATABASE_URL=postgresql://... --from-literal JWT_SECRET=mysecret"
  exit 1
fi

NAMESPACE="$1"
SECRET_NAME="$2"
shift 2

KUBECONFIG="${KUBECONFIG:-/home/son/.kube/config}"
export KUBECONFIG

# Ensure namespace exists
kubectl get namespace "${NAMESPACE}" &>/dev/null || \
  kubectl create namespace "${NAMESPACE}"

# Build kubectl command
CMD="kubectl create secret generic ${SECRET_NAME} -n ${NAMESPACE}"

while [ $# -gt 0 ]; do
  case "$1" in
    --from-env-file)
      if [ ! -f "$2" ]; then
        echo "ERROR: File not found: $2"
        exit 1
      fi
      CMD="${CMD} --from-env-file=$2"
      shift 2
      ;;
    --from-literal)
      CMD="${CMD} --from-literal=$2"
      shift 2
      ;;
    *)
      echo "Unknown option: $1"
      exit 1
      ;;
  esac
done

# Delete existing secret if it exists
if kubectl get secret "${SECRET_NAME}" -n "${NAMESPACE}" &>/dev/null; then
  echo "Secret ${SECRET_NAME} already exists in ${NAMESPACE}. Replacing..."
  kubectl delete secret "${SECRET_NAME}" -n "${NAMESPACE}"
fi

echo "Creating secret ${SECRET_NAME} in namespace ${NAMESPACE}..."
eval "${CMD}"
echo "Done."
