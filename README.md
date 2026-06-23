# ArgoCD vs FluxCD — GitOps Tooling Comparison

A hands-on technical comparison of the two leading GitOps tools for Kubernetes. Both tools reconcile cluster state from a Git repository, but they differ significantly in architecture, UX, and the scenarios where each shines.

---

## Prerequisites

- Docker Desktop with Kind enabled
- `kubectl` configured against your cluster
- `helm` (see installation below)
- `flux` CLI (see FluxCD section)
- `argocd` CLI (optional, see ArgoCD section)

---

## Cluster Setup

This demo uses a 3-node Kind cluster (1 control-plane + 2 workers).

```bash
kind create cluster --config kind/cluster.yaml
kubectl get nodes
```

---

## 1. Helm Installation

Helm is required to install both ArgoCD and FluxCD.

### macOS (Homebrew)

```bash
brew install helm
```

### Linux

```bash
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
```

### Windows (Chocolatey)

```bash
choco install kubernetes-helm
```

### Verify

```bash
helm version
```

---

## 2. ArgoCD

### Add the Helm repository

```bash
helm repo add argo https://argoproj.github.io/argo-helm
helm repo update
```

### Install (latest version)

```bash
kubectl create namespace argocd

helm install argocd argo/argo-cd \
  --namespace argocd \
  --set server.service.type=ClusterIP
```

### Verify the installation

```bash
kubectl get pods -n argocd
kubectl wait --for=condition=available deployment/argocd-server -n argocd --timeout=120s
```

### Access the UI

```bash
kubectl port-forward svc/argocd-server -n argocd 8080:443
```

Open [https://localhost:8080](https://localhost:8080) in your browser.

### Get the initial admin password

```bash
kubectl get secret argocd-initial-admin-secret -n argocd \
  -o jsonpath="{.data.password}" | base64 -d && echo
```

Login with username `admin` and the password above.

### Install the ArgoCD CLI (optional)

```bash
# macOS
brew install argocd

# Linux
curl -sSL -o argocd https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64
chmod +x argocd && sudo mv argocd /usr/local/bin/
```

### Deploy the sample app via ArgoCD

```bash
kubectl apply -f argocd/app/application.yaml
```

ArgoCD will detect the `sample-app/manifests` path in this repository and sync it automatically.

---

## 3. FluxCD

### Add the Helm repository

```bash
helm repo add fluxcd-community https://fluxcd-community.github.io/helm-charts
helm repo update
```

### Install (latest version)

```bash
kubectl create namespace flux-system

helm install flux fluxcd-community/flux2 \
  --namespace flux-system \
  --set imageAutomationController.create=true \
  --set imageReflectorController.create=true
```

### Verify the installation

```bash
kubectl get pods -n flux-system
```

### Install the Flux CLI

```bash
# macOS
brew install fluxcd/tap/flux

# Linux
curl -s https://fluxcd.io/install.sh | sudo bash
```

### Verify the CLI

```bash
flux check
```

### Deploy the sample app via FluxCD

```bash
kubectl apply -f fluxcd/app/gitrepository.yaml
kubectl apply -f fluxcd/app/kustomization.yaml
```

Check sync status:

```bash
flux get sources git
flux get kustomizations
```

---

## 4. Sample App

A minimal nginx deployment used as the reconciliation target for both tools.

```
sample-app/
├── src/
│   ├── index.html
│   └── Dockerfile
└── manifests/
    ├── namespace.yaml
    ├── deployment.yaml
    └── service.yaml
```

Both ArgoCD and FluxCD point to `sample-app/manifests` in this repository. Any change pushed to `main` will be automatically reconciled in the cluster.

---

## 5. ArgoCD vs FluxCD — Quick Comparison

| | ArgoCD | FluxCD |
|---|---|---|
| **Architecture** | Centralized server + UI | Distributed controllers (no central server) |
| **UI** | Rich built-in web UI | No built-in UI (integrates with Grafana/Weave GitOps) |
| **CLI** | `argocd` CLI | `flux` CLI |
| **Sync model** | Pull + manual/auto trigger | Pure pull (controller-based) |
| **Multi-tenancy** | Projects + RBAC built-in | Namespace isolation via controllers |
| **Helm support** | Native | Via HelmRelease CRD |
| **Kustomize support** | Native | Native |
| **Image automation** | Via Argo Image Updater (separate) | Built-in controller |
| **Community & adoption** | Larger, CNCF Graduated | Smaller but growing, CNCF Graduated |
| **Best for** | Teams wanting a UI, centralized control | GitOps purists, automation-heavy pipelines |

### When ArgoCD makes more sense
- Your team wants a visual dashboard to track app health across clusters
- You need fine-grained RBAC with project isolation out of the box
- You manage many apps across multiple clusters from a single control plane

### When FluxCD makes more sense
- You want a fully declarative, UI-less GitOps setup with no extra servers to manage
- You need native image update automation (tag updates committed back to Git automatically)
- You are running Flux as part of a larger platform with Grafana/Prometheus already in place
- Minimal cluster footprint matters (Flux controllers are lightweight)

---

## Cleanup

```bash
# Remove ArgoCD
helm uninstall argocd -n argocd
kubectl delete namespace argocd

# Remove FluxCD
helm uninstall flux -n flux-system
kubectl delete namespace flux-system

# Delete the Kind cluster
kind delete cluster --name gitops-demo
```
