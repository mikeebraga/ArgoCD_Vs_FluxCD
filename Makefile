.PHONY: cluster-up argocd-install argocd-image-updater argocd-app \
        fluxcd-install fluxcd-app fluxcd-image-automation \
        compare-resources tag-v1 tag-v2 clean

# --- Kind cluster ---
cluster-up:
	kind create cluster --config kind/cluster.yaml

# --- ArgoCD ---
argocd-install:
	helm repo add argo https://argoproj.github.io/argo-helm
	helm repo update
	kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
	helm install argocd argo/argo-cd --namespace argocd --set server.service.type=ClusterIP
	kubectl wait --for=condition=available deployment/argocd-server -n argocd --timeout=180s

argocd-image-updater:
	helm install argocd-image-updater argo/argocd-image-updater \
	  --namespace argocd \
	  --values argocd/image-updater/values.yaml
	bash argocd/image-updater/ghcr-secret.sh

argocd-app:
	kubectl apply -f argocd/app/application.yaml

argocd-ui:
	kubectl port-forward svc/argocd-server -n argocd 8080:443

argocd-password:
	kubectl get secret argocd-initial-admin-secret -n argocd \
	  -o jsonpath="{.data.password}" | base64 -d && echo

# --- FluxCD ---
fluxcd-install:
	helm repo add fluxcd-community https://fluxcd-community.github.io/helm-charts
	helm repo update
	kubectl create namespace flux-system --dry-run=client -o yaml | kubectl apply -f -
	helm install flux fluxcd-community/flux2 \
	  --namespace flux-system \
	  --set imageAutomationController.create=true \
	  --set imageReflectorController.create=true
	kubectl wait --for=condition=available deployment/source-controller -n flux-system --timeout=180s

fluxcd-app:
	kubectl apply -f fluxcd/app/gitrepository.yaml
	kubectl apply -f fluxcd/app/kustomization.yaml

fluxcd-image-automation:
	bash fluxcd/image-automation/ghcr-secret.sh
	kubectl apply -f fluxcd/image-automation/imagerepository.yaml
	kubectl apply -f fluxcd/image-automation/imagepolicy.yaml
	kubectl apply -f fluxcd/image-automation/imageupdateautomation.yaml

fluxcd-status:
	flux get sources git
	flux get kustomizations
	flux get images all -n flux-system

# --- Demo: trigger an image update ---
tag-v1:
	git tag v1.0.0 && git push origin v1.0.0

tag-v2:
	git tag v2.0.0 && git push origin v2.0.0

# --- Resource comparison ---
compare-resources:
	bash scripts/resource-compare.sh

# --- Cleanup ---
clean:
	helm uninstall argocd -n argocd || true
	helm uninstall argocd-image-updater -n argocd || true
	helm uninstall flux -n flux-system || true
	kubectl delete namespace argocd flux-system demo || true
	kind delete cluster --name gitops-demo || true
