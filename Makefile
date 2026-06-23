.PHONY: cluster-up argocd-install argocd-app fluxcd-install fluxcd-app clean

# --- Kind cluster ---
cluster-up:
	kind create cluster --config kind/cluster.yaml

# --- ArgoCD ---
argocd-install:
	kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
	kubectl wait --for=condition=available deployment/argocd-server -n argocd --timeout=120s

argocd-ui:
	kubectl port-forward svc/argocd-server -n argocd 8080:443

argocd-password:
	kubectl get secret argocd-initial-admin-secret -n argocd -o jsonpath="{.data.password}" | base64 -d && echo

argocd-app:
	kubectl apply -f argocd/app/application.yaml

# --- FluxCD ---
fluxcd-install:
	flux install

fluxcd-app:
	kubectl apply -f fluxcd/app/gitrepository.yaml
	kubectl apply -f fluxcd/app/kustomization.yaml

fluxcd-status:
	flux get kustomizations
	flux get sources git

# --- Cleanup ---
clean:
	kind delete cluster --name gitops-demo
