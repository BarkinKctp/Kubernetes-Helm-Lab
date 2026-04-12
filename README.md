[![Minikube](https://img.shields.io/badge/Minikube-3b82f6?logo=kubernetes&logoColor=white)](https://minikube.sigs.k8s.io/docs/start/)
[![Helm](https://img.shields.io/badge/Helm-f97316?logo=helm&logoColor=white)](https://helm.sh/docs/intro/install/)
[![kubectl](https://img.shields.io/badge/kubectl-06b6d4?logo=kubernetes&logoColor=white)](https://kubernetes.io/docs/tasks/tools/)
[![ArgoCD](https://img.shields.io/badge/ArgoCD-a855f7?logo=argo&logoColor=white)](https://argoproj.github.io/cd/)
[![AWS](https://img.shields.io/badge/AWS-ff9900?logo=amazonaws&logoColor=white)](https://aws.amazon.com/eks/)

# Kubernetes Lab - Webapp

Flask webapp demonstrating Kubernetes deployment patterns with Helm, Kustomize, and ArgoCD.

## Quick Start

Prerequisites: Minikube, Helm, kubectl

```bash
minikube start --driver=docker
```

### Alias (optional)

alias k=kubectl

## Deployment Options

### Helm (Default)

```bash
helm install webapp helm-webapp/ --values helm-webapp/values.yaml

k port-forward svc/webapp 8888:80
# Open: http://localhost:8888
```

### Helm with Dev Overlay

```bash

k create namespace dev

helm install mywebapp-release-dev helm-webapp/ --values helm-webapp/values.yaml -f helm-webapp/values-dev.yaml -n dev

k port-forward svc/webapp 8888:80 -n dev
# Open: http://localhost:8888
```

### Kustomize

Environment-specific overlays (config, replicas, patches applied to base).

```bash

kubectl apply -k kustom-webapp/overlays/prod

k port-forward svc/webapp 8888:80
# Open: http://localhost:8888
```

### Static Manifests

```bash
kubectl apply -f Deployment/v1.yaml
kubectl apply -f Deployment/v2.yaml
kubectl apply -f Deployment/v3.yaml

k port-forward svc/webapp 8888:80
# Open: http://localhost:8888
```

## Manage

```bash
# Expose via LoadBalancer (local)
minikube tunnel
k get svc

# Cleanup
helm uninstall webapp
helm uninstall mywebapp-release-dev -n dev
```

## Project Structure

- **helm-webapp/** - Helm chart with environment overlays
- **kustom-webapp/** - Kustomize base + dev/prod overlays with replacements
- **Deployment/** - Static manifests (v1-v3 progression)
- **Dockerapp/** - Flask app source

## Features

Security: Non-root user, read-only filesystem  
Availability: HPA, PDB, rolling updates  
Configuration: Immutable ConfigMaps, environment-specific overlays

## ArgoCD Documentation

- [ArgoCD GitOps Deployment](docs/ArgoCd.md) - ConfigMap immutability pattern with ArgoCD

## Troubleshooting

- **Pods stuck in CrashLoopBackOff** — Check logs: `k logs <pod-name>`
- **Cannot access app** — Ensure port-forward or minikube tunnel is running
- **YAML files not recognized** — Use `.yaml` extension (not `.yml`)
