# ArgoCD vs FluxCD — GitOps Tooling Comparison

A hands-on technical comparison focused on one of the most impactful practical differences between the two tools: **built-in image update automation**. FluxCD handles this natively. ArgoCD requires a separate component (Argo Image Updater) to achieve the same result.

---

## Prerequisites

- Docker Desktop with Kind enabled
- `kubectl`
- `helm` (see below)
- `flux` CLI (see FluxCD section)
- GitHub account with a PAT scoped to `read:packages` + `write:packages`

---

## 1. Helm Installation

### macOS

```bash
brew install helm
```

### Linux

```bash
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
```

### Windows

```bash
choco install kubernetes-helm
```

```bash
helm version
```

---

## 2. Cluster Setup

```bash
kind create cluster --config kind/cluster.yaml
kubectl get nodes
# NAME                    STATUS   ROLES
# gitops-demo-control-plane   Ready    control-plane
# gitops-demo-worker          Ready    <none>
# gitops-demo-worker2         Ready    <none>
```

---

## 3. Sample App

A minimal nginx app with two visible versions to make the demo obvious.

| Version | Accent colour | Badge |
|---------|--------------|-------|
| `v1.0.0` | Green | — |
| `v2.0.0` | Orange | "Auto-updated by Flux Image Automation" |

Both versions are in `sample-app/src/v1` and `sample-app/src/v2`. The GitHub Actions workflow in `.github/workflows/build-push.yaml` builds and pushes to GHCR automatically when you push a `v*` tag.

```
sample-app/
├── src/
│   ├── v1/  →  ghcr.io/mikeebraga/gitops-demo:v1.0.0
│   └── v2/  →  ghcr.io/mikeebraga/gitops-demo:v2.0.0
└── manifests/
    ├── namespace.yaml
    ├── deployment.yaml   ← contains the $imagepolicy marker for Flux
    └── service.yaml
```

### Push the images (GitHub Actions does this on tag push)

```bash
make tag-v1   # git tag v1.0.0 + git push origin v1.0.0
make tag-v2   # git tag v2.0.0 + git push origin v2.0.0
```

---

## 4. ArgoCD

### Install

```bash
make argocd-install
# or manually:
helm repo add argo https://argoproj.github.io/argo-helm && helm repo update
kubectl create namespace argocd
helm install argocd argo/argo-cd --namespace argocd --set server.service.type=ClusterIP
```

### Access the UI

```bash
make argocd-ui          # port-forward to https://localhost:8080
make argocd-password    # print the initial admin password
```

### Deploy the sample app

```bash
make argocd-app
# kubectl apply -f argocd/app/application.yaml
```

ArgoCD syncs `sample-app/manifests` from this repo and deploys the app. It will stay on **v1.0.0** until the manifest is updated manually — or until Argo Image Updater is installed.

### Image automation with Argo Image Updater (extra component required)

```bash
# 1. Create the GHCR credential secret
bash argocd/image-updater/ghcr-secret.sh

# 2. Install Argo Image Updater via Helm
helm install argocd-image-updater argo/argocd-image-updater \
  --namespace argocd \
  --values argocd/image-updater/values.yaml

# or:
make argocd-image-updater
```

The Application manifest (`argocd/app/application.yaml`) already has the required annotations. With Image Updater running, ArgoCD will now detect new semver tags and commit the update back to Git.

> **This is the friction point.** What required 3 steps and an extra Helm release in ArgoCD is built into FluxCD out of the box.

---

## 5. FluxCD

### Install

**Step 1 — Add the Helm repo**

```bash
helm repo add fluxcd-community https://fluxcd-community.github.io/helm-charts
helm repo update
```

**Step 2 — Install Flux with image automation controllers**

```bash
kubectl create namespace flux-system

helm install flux fluxcd-community/flux2 \
  --namespace flux-system \
  --set imageAutomationController.create=true \
  --set imageReflectorController.create=true
```

**Step 3 — Wait for all pods to be running**

```bash
kubectl get pods -n flux-system --watch
```

You should see 6 pods reach `Running` status:

```
helm-controller                  Running
image-automation-controller      Running
image-reflector-controller       Running
kustomize-controller             Running
notification-controller          Running
source-controller                Running
```

**Step 4 — Install the Flux CLI**

```bash
# macOS
brew install fluxcd/tap/flux

# Linux
curl -s https://fluxcd.io/install.sh | sudo bash
```

**Step 5 — Verify everything is healthy**

```bash
flux check
```

All checks should return `✔`. If any controller is not ready, wait a few seconds and re-run.

### Deploy the sample app

```bash
make fluxcd-app
# kubectl apply -f fluxcd/app/gitrepository.yaml
# kubectl apply -f fluxcd/app/kustomization.yaml
```

### Image automation — native, no extra install

```bash
make fluxcd-image-automation
# This runs:
#   bash fluxcd/image-automation/ghcr-secret.sh      ← GHCR auth
#   kubectl apply -f fluxcd/image-automation/imagerepository.yaml
#   kubectl apply -f fluxcd/image-automation/imagepolicy.yaml
#   kubectl apply -f fluxcd/image-automation/imageupdateautomation.yaml
```

Check status:

```bash
make fluxcd-status
# flux get sources git
# flux get kustomizations
# flux get images all -n flux-system
```

### How it works

```
┌─────────────────────────────────────────────────────────┐
│                    Flux Image Automation                 │
│                                                         │
│  GHCR registry                                          │
│    └── ImageRepository (polls every 1m)                 │
│          └── ImagePolicy (semver >=v1.0.0)              │
│                └── ImageUpdateAutomation                │
│                      ├── rewrites deployment.yaml tag   │
│                      ├── commits to main                │
│                      └── Kustomization reconciles       │
└─────────────────────────────────────────────────────────┘
```

The key is the marker comment in `sample-app/manifests/deployment.yaml`:

```yaml
image: ghcr.io/mikeebraga/gitops-demo:v1.0.0 # {"$imagepolicy": "flux-system:gitops-demo"}
```

When Flux detects `v2.0.0` on GHCR, it rewrites that line, commits to `main`, and the Kustomization reconciles the cluster — all without any manual intervention.

---

## 6. The Demo: Push v2 and Watch Flux React

```bash
# 1. Ensure both tools are installed and the app is running on v1.0.0
kubectl get pods -n demo

# 2. Push the v2 tag — GitHub Actions builds and pushes ghcr.io/mikeebraga/gitops-demo:v2.0.0
make tag-v2

# 3. Watch Flux detect the new tag (within ~1 minute)
flux get images all -n flux-system

# 4. Flux commits the tag update to Git automatically — check your repo
# git log --oneline -3

# 5. Flux reconciles the cluster
flux get kustomizations --watch

# 6. Port-forward to see the app on v2.0.0
kubectl port-forward svc/gitops-demo -n demo 8081:80
# open http://localhost:8081
```

With ArgoCD + Image Updater doing the equivalent — the steps are the same, but the setup required an extra component and extra credentials configuration.

---

## 7. Resource Comparison

```bash
make compare-resources
# or: bash scripts/resource-compare.sh
```

Example output after both tools are installed:

```
--- ArgoCD pods (namespace: argocd) ---
argocd-application-controller    Running
argocd-applicationset-controller Running
argocd-dex-server                Running
argocd-notifications-controller  Running
argocd-redis                     Running
argocd-repo-server               Running
argocd-server                    Running    ← API server + UI
argocd-image-updater             Running    ← extra install for image automation
Total pods: 8

--- FluxCD pods (namespace: flux-system) ---
helm-controller                  Running
image-automation-controller      Running    ← built-in
image-reflector-controller       Running    ← built-in
kustomize-controller             Running
notification-controller          Running
source-controller                Running
Total pods: 6
```

ArgoCD carries Redis, Dex (SSO), and a full API server — which give you the rich UI and centralised control, but at a resource cost. FluxCD's controllers are narrowly scoped and significantly lighter.

---

## 8. When to choose which

### Choose ArgoCD when
- Your team wants a visual dashboard to track app health across clusters
- You need fine-grained RBAC with project isolation out of the box
- You manage many apps across multiple clusters from a single control plane
- Non-engineers need visibility into deployment state

### Choose FluxCD when
- You want a fully declarative, UI-less GitOps setup with no extra servers to manage
- **Image update automation is a core part of your workflow** — this is Flux's clearest win
- You are already running Grafana/Prometheus and don't need a separate UI
- Minimal cluster footprint matters (Flux controllers are lightweight)
- You prefer every piece of config to live as a CRD in Git, nothing centralised

---

## Cleanup

```bash
make clean
# Removes ArgoCD, ArgoCD Image Updater, FluxCD, demo namespace, and the Kind cluster
```
