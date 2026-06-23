#!/bin/bash
# Run this once before applying image automation manifests.
# GITHUB_TOKEN needs read:packages scope.
# Generate one at: https://github.com/settings/tokens

read -rsp "GitHub Personal Access Token (read:packages): " GITHUB_TOKEN
echo

kubectl create secret docker-registry ghcr-auth \
  --namespace flux-system \
  --docker-server=ghcr.io \
  --docker-username=mikeebraga \
  --docker-password="${GITHUB_TOKEN}"
