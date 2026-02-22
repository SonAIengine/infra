#!/bin/bash
set -euo pipefail

# =============================================================================
# Cluster Bootstrap Script
# Installs ArgoCD, cert-manager, and applies shared cluster resources
# Prerequisites: K3s installed, kubectl/helm available
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INFRA_DIR="$(dirname "$SCRIPT_DIR")"
KUBECONFIG="${KUBECONFIG:-/home/son/.kube/config}"

export KUBECONFIG

echo "==> Cluster bootstrap starting..."
echo "    KUBECONFIG: ${KUBECONFIG}"
echo "    INFRA_DIR:  ${INFRA_DIR}"

# -----------------------------------------------------------------------------
# 1. Install cert-manager
# -----------------------------------------------------------------------------
echo ""
echo "==> [1/4] Installing cert-manager..."
if kubectl get namespace cert-manager &>/dev/null; then
  echo "    cert-manager namespace exists, skipping install"
else
  helm repo add jetstack https://charts.jetstack.io --force-update
  helm repo update
  helm install cert-manager jetstack/cert-manager \
    --namespace cert-manager \
    --create-namespace \
    --set crds.enabled=true \
    --wait
fi

echo "    Applying ClusterIssuer..."
kubectl apply -f "${INFRA_DIR}/cluster/cert-manager/cluster-issuer.yaml"

# -----------------------------------------------------------------------------
# 2. Apply Traefik middleware
# -----------------------------------------------------------------------------
echo ""
echo "==> [2/4] Applying Traefik default headers..."
kubectl apply -f "${INFRA_DIR}/cluster/traefik/default-headers.yaml"

# -----------------------------------------------------------------------------
# 3. Install ArgoCD
# -----------------------------------------------------------------------------
echo ""
echo "==> [3/4] Installing ArgoCD..."
if kubectl get namespace argocd &>/dev/null; then
  echo "    argocd namespace exists, skipping install"
else
  helm repo add argo https://argoproj.github.io/argo-helm --force-update
  helm repo update
  helm install argocd argo/argo-cd \
    --namespace argocd \
    --create-namespace \
    -f "${INFRA_DIR}/cluster/argocd/install.yaml" \
    --wait
fi

# -----------------------------------------------------------------------------
# 4. Apply ArgoCD project and ApplicationSet
# -----------------------------------------------------------------------------
echo ""
echo "==> [4/4] Applying ArgoCD configuration..."
kubectl apply -f "${INFRA_DIR}/cluster/argocd/projects.yaml"
kubectl apply -f "${INFRA_DIR}/cluster/argocd/applicationset.yaml"

# -----------------------------------------------------------------------------
# Print ArgoCD initial admin password
# -----------------------------------------------------------------------------
echo ""
echo "==> Bootstrap complete!"
echo ""
echo "ArgoCD admin password:"
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" 2>/dev/null | base64 -d && echo "" || \
  echo "  (secret not found - may have been deleted)"
echo ""
echo "Access ArgoCD UI via: https://argocd.infoedu.co.kr"
echo "Or port-forward: kubectl port-forward svc/argocd-server -n argocd 8080:443"
