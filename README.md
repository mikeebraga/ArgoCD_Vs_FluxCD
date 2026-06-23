# ArgoCD vs FluxCD — A GitOps Comparison

> **Note:** This is an experimental hands-on study, not a complete article. It is a work in progress built on a local Kubernetes cluster using real tooling. Numbers and conclusions are based on the environment described below.

---

## Context

Both ArgoCD and FluxCD are CNCF-graduated GitOps tools for Kubernetes. ArgoCD is the most widely adopted, but that doesn't make FluxCD irrelevant — there are real scenarios where Flux is the better choice.

This study focuses on two concrete angles:

1. **Built-in image update automation** — the feature where the gap between the two tools is most visible
2. **Resource footprint** — measured on a real cluster, not estimated

---

## Environment

| | |
|---|---|
| Machine | MacBook Air M4 — 16GB RAM |
| Cluster | Kind (Kubernetes in Docker) via Docker Desktop |
| Nodes | 1 control-plane + 1 worker |
| Kubernetes | v1.34.3 |
| ArgoCD | Installed via Helm (`argo/argo-cd`) |
| FluxCD | Installed via Helm (`fluxcd-community/flux2`) |

---

## Setup

### 1. Helm

```bash
# macOS
brew install helm

# Linux
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# Windows
choco install kubernetes-helm

helm version
```

### 2. Cluster

```bash
kind create cluster --config kind/cluster.yaml
kubectl get nodes
```

### 3. ArgoCD

```bash
helm repo add argo https://argoproj.github.io/argo-helm
helm repo update

kubectl create namespace argocd

helm install argocd argo/argo-cd \
  --namespace argocd \
  --set server.service.type=ClusterIP

kubectl wait --for=condition=available deployment/argocd-server -n argocd --timeout=180s
```

Access the UI:

```bash
# terminal 1 — port forward
kubectl port-forward svc/argocd-server -n argocd 8080:443

# terminal 2 — get the initial password
kubectl get secret argocd-initial-admin-secret -n argocd \
  -o jsonpath="{.data.password}" | base64 -d && echo
```

Open **https://localhost:8080** — login with `admin` and the password above.

### 4. FluxCD

```bash
helm repo add fluxcd-community https://fluxcd-community.github.io/helm-charts
helm repo update

kubectl create namespace flux-system

helm install flux fluxcd-community/flux2 \
  --namespace flux-system \
  --set imageAutomationController.create=true \
  --set imageReflectorController.create=true

kubectl get pods -n flux-system --watch
```

Wait until all 6 pods are `Running`, then install the CLI:

```bash
# macOS
brew install fluxcd/tap/flux

# Linux
curl -s https://fluxcd.io/install.sh | sudo bash

flux check
```

---

## The Sample App

A minimal nginx app with two visually distinct versions — the difference is obvious the moment you open the browser.

| Version | Colour | Notes |
|---------|--------|-------|
| `v1.0.0` | Green | Initial deploy |
| `v2.0.0` | Orange | Includes "Auto-updated" badge |

Both versions live in `sample-app/src/v1` and `sample-app/src/v2`. A GitHub Actions workflow builds and pushes the image to GHCR on every `v*` tag push.

```
sample-app/
├── src/
│   ├── v1/  →  ghcr.io/mikeebraga/gitops-demo:v1.0.0
│   └── v2/  →  ghcr.io/mikeebraga/gitops-demo:v2.0.0
└── manifests/
    ├── namespace.yaml
    ├── deployment.yaml
    └── service.yaml
```

---

## Deploying with FluxCD

FluxCD works in two steps. First you tell it where your Git repository is, then you tell it what to apply from it.

**Step 1 — GitRepository:** points Flux at this repo and branch.

```bash
kubectl apply -f fluxcd/app/gitrepository.yaml
kubectl get gitrepository -n flux-system
```

You should see `READY: True` — Flux has cloned the repo.

**Step 2 — Kustomization:** tells Flux which path to apply and where in the cluster.

```bash
kubectl apply -f fluxcd/app/kustomization.yaml
kubectl get kustomization -n flux-system
```

Once `READY: True`, the `demo` namespace and the app are live:

```bash
kubectl get pods -n demo
```

---

## Demonstrating GitOps Reconciliation

With Flux watching the repo, any change pushed to `main` is automatically applied to the cluster within minutes — no `kubectl apply` needed.

To prove it, we updated `deployment.yaml` to reference `v2.0.0` and pushed to `main`. Flux detected the change on its next reconciliation cycle (every 5 minutes by default) and rolled out the new version automatically.

```bash
# watch the rollout happen on its own
kubectl get pods -n demo --watch
```

Then port-forward to see the visual change:

```bash
kubectl port-forward svc/gitops-demo -n demo 8081:80
# open http://localhost:8081
```

The orange `v2.0.0` page confirms the update happened — triggered only by a Git push.

---

## Where FluxCD Pulls Ahead

### 1. Image Update Automation

This is the most concrete difference between the two tools.

**With FluxCD**, image automation is built in. Three CRDs and you're done:

| CRD | What it does |
|-----|-------------|
| `ImageRepository` | Polls GHCR every minute for new tags |
| `ImagePolicy` | Filters tags by semver range — picks the latest |
| `ImageUpdateAutomation` | Rewrites the image tag in Git, commits, pushes |

The deployment manifest has a marker comment that tells Flux exactly which line to rewrite:

```yaml
image: ghcr.io/mikeebraga/gitops-demo:v2.0.0 # {"$imagepolicy": "flux-system:gitops-demo"}
```

The full automation flow:

```
You push a git tag (v2.0.0)
      ↓
GitHub Actions builds and pushes the image to GHCR
      ↓
Flux ImageRepository detects the new tag (within 1 min)
      ↓
Flux ImageUpdateAutomation rewrites deployment.yaml in Git
      ↓
Flux Kustomization reconciles the cluster
      ↓
Pods update — no manual intervention at any point
```

**With ArgoCD**, this requires installing a separate component — Argo Image Updater — as an additional Helm release with its own credentials and configuration. The Application manifest then needs annotations for it to work. It is solvable, but it is extra moving parts that Flux simply does not have.

```bash
# ArgoCD: extra install required
helm install argocd-image-updater argo/argocd-image-updater \
  --namespace argocd \
  --values argocd/image-updater/values.yaml
```

### 2. Resource Footprint

Measured on this cluster with both tools idle after deploying the same app:

**ArgoCD — 7 pods**

| Pod | Memory |
|-----|--------|
| application-controller | 168Mi |
| server (UI + API) | 48Mi |
| repo-server | 35Mi |
| applicationset-controller | 30Mi |
| dex-server (SSO) | 30Mi |
| notifications-controller | 26Mi |
| redis | 10Mi |
| **Total** | **~347Mi** |

**FluxCD — 6 pods**

| Pod | Memory |
|-----|--------|
| source-controller | 27Mi |
| notification-controller | 26Mi |
| image-reflector-controller | 26Mi |
| kustomize-controller | 25Mi |
| helm-controller | 21Mi |
| image-automation-controller | 17Mi |
| **Total** | **~142Mi** |

**Flux uses roughly 2.4x less memory** — and that gap widens if you add Argo Image Updater to the ArgoCD side.

ArgoCD's heavier footprint is not waste — it comes from running a full API server, a web UI, Redis for caching, and Dex for SSO. Those components power the dashboard. If you need the dashboard, they are worth it. If you don't, you are paying for something you are not using.

---

## When to Choose ArgoCD

- Your team wants a visual dashboard to track app health across clusters
- You need fine-grained RBAC with project isolation out of the box
- You manage many applications across multiple clusters from a single control plane
- Non-engineers need visibility into deployment state

## When to Choose FluxCD

- You want a fully declarative, UI-less GitOps setup with no extra servers to manage
- **Image update automation is a core part of your workflow** — this is Flux's clearest win
- You are already running Grafana and Prometheus and do not need a separate UI
- Minimal cluster footprint matters — edge clusters, resource-constrained environments
- You prefer every piece of configuration to live as a CRD in Git, nothing centralised

---

## Cleanup

```bash
# Remove ArgoCD
helm uninstall argocd -n argocd
kubectl delete namespace argocd

# Remove FluxCD
helm uninstall flux -n flux-system
kubectl delete namespace flux-system

# Remove the demo app
kubectl delete namespace demo

# Delete the Kind cluster
kind delete cluster --name gitops-demo
```

---

## Repository Structure

```
.
├── .github/workflows/
│   └── build-push.yaml          # builds v1/v2 image on git tag push
├── argocd/
│   ├── app/application.yaml     # ArgoCD Application CR (with image updater annotations)
│   └── image-updater/           # extra Helm values + secret for Argo Image Updater
├── fluxcd/
│   ├── app/                     # GitRepository + Kustomization CRs
│   └── image-automation/        # ImageRepository, ImagePolicy, ImageUpdateAutomation
├── sample-app/
│   ├── src/v1 and v2/           # Dockerfile + HTML per version
│   └── manifests/               # Deployment, Service, Namespace
├── scripts/
│   └── resource-compare.sh      # kubectl top side-by-side
├── kind/cluster.yaml            # 3-node Kind cluster config
└── Makefile                     # one-liners for every step
```
