#!/bin/bash
set -euo pipefail

# =============================================================================
# New App Onboarding Script
# Scaffolds a new application from the template
# Usage: ./onboard-app.sh <app-name> <domain>
# =============================================================================

if [ $# -lt 2 ]; then
  echo "Usage: $0 <app-name> <domain>"
  echo "Example: $0 my-app my-app.example.com"
  exit 1
fi

APP_NAME="$1"
DOMAIN="$2"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INFRA_DIR="$(dirname "$SCRIPT_DIR")"
APPS_DIR="${INFRA_DIR}/apps"
TEMPLATE="${APPS_DIR}/_template/values.yaml"
TARGET_DIR="${APPS_DIR}/${APP_NAME}"

if [ -d "${TARGET_DIR}" ]; then
  echo "ERROR: ${TARGET_DIR} already exists"
  exit 1
fi

if [ ! -f "${TEMPLATE}" ]; then
  echo "ERROR: Template not found at ${TEMPLATE}"
  exit 1
fi

echo "==> Creating app: ${APP_NAME}"
echo "    Domain: ${DOMAIN}"
echo "    Directory: ${TARGET_DIR}"

mkdir -p "${TARGET_DIR}"
sed \
  -e "s/<app-name>/${APP_NAME}/g" \
  -e "s/<your-domain.com>/${DOMAIN}/g" \
  "${TEMPLATE}" > "${TARGET_DIR}/values.yaml"

echo ""
echo "Done! Next steps:"
echo "  1. Edit ${TARGET_DIR}/values.yaml to configure your app"
echo "  2. Create secrets: ./scripts/seal-secret.sh ${APP_NAME} ${APP_NAME}-app-secret --from-literal KEY=VALUE"
echo "  3. Commit and push - ArgoCD will auto-detect the new app"
echo ""
echo "Validate with:"
echo "  helm template ${APP_NAME} charts/web-app -f apps/${APP_NAME}/values.yaml"
