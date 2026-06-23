#!/bin/bash
# Compares pod count and resource usage between ArgoCD and FluxCD.
# Requires metrics-server: kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml

echo "============================================================"
echo "  GitOps Tooling Resource Comparison"
echo "============================================================"

echo ""
echo "--- ArgoCD pods ---"
kubectl get pods -n argocd --no-headers | awk '{print $1, $3}'
ARGO_COUNT=$(kubectl get pods -n argocd --no-headers | wc -l | tr -d ' ')
echo "Total pods: $ARGO_COUNT"

echo ""
echo "--- FluxCD pods ---"
kubectl get pods -n flux-system --no-headers | awk '{print $1, $3}'
FLUX_COUNT=$(kubectl get pods -n flux-system --no-headers | wc -l | tr -d ' ')
echo "Total pods: $FLUX_COUNT"

echo ""
echo "--- Resource usage (kubectl top) ---"
echo ""
echo "[ArgoCD - namespace: argocd]"
kubectl top pods -n argocd --sort-by=memory 2>/dev/null || echo "metrics-server not available"

echo ""
echo "[FluxCD - namespace: flux-system]"
kubectl top pods -n flux-system --sort-by=memory 2>/dev/null || echo "metrics-server not available"

echo ""
echo "============================================================"
echo "  Summary"
echo "============================================================"
echo "ArgoCD pods : $ARGO_COUNT"
echo "FluxCD pods : $FLUX_COUNT"
echo ""
echo "Note: ArgoCD includes a full API server, UI, Redis, and Dex."
echo "      FluxCD runs independent lightweight controllers only."
echo "============================================================"
