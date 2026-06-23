#!/bin/bash
# Same credential need as Flux, but scoped to the argocd namespace.

read -rsp "GitHub Personal Access Token (read:packages): " GITHUB_TOKEN
echo

kubectl create secret generic ghcr-auth \
  --namespace argocd \
  --from-literal=token="${GITHUB_TOKEN}"
