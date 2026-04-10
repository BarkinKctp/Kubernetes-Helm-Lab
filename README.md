[![Minikube](https://img.shields.io/badge/Minikube-3b82f6?logo=kubernetes&logoColor=white)](https://minikube.sigs.k8s.io/docs/start/)
[![Helm](https://img.shields.io/badge/Helm-f97316?logo=helm&logoColor=white)](https://helm.sh/docs/intro/install/)
[![kubectl](https://img.shields.io/badge/kubectl-06b6d4?logo=kubernetes&logoColor=white)](https://kubernetes.io/docs/tasks/tools/)
[![ArgoCD](https://img.shields.io/badge/ArgoCD-a855f7?logo=argo&logoColor=white)](https://argoproj.github.io/cd/)
[![AWS](https://img.shields.io/badge/AWS-ff9900?logo=amazonaws&logoColor=white)](https://aws.amazon.com/eks/)

# Kubernetes Lab - Webapp

A containerized Flask webapp deployed on Kubernetes with Helm charts and progressive deployment examples.

## Prerequisites

- Minikube, Helm, kubectl installed

## Quick Start

### Setup (optional alias)

```bash
alias k=kubectl
```

### Option 1: Helm Deployment

#### Basic (default namespace)

```bash

minikube start --driver=docker

helm install webapp-release webapp/ --values webapp/values.yml
```

**Access the app:**

```bash

k port-forward svc/webapp 8888:80

# Open: http://localhost:8888

```

#### With Dev Namespace

```bash

k create namespace dev

helm install mywebapp-release-dev webapp/ --values webapp/values.yml -f webapp/values-dev.yml -n dev

```

**Access the app:**

```bash
k port-forward svc/webapp 8888:80 -n dev
# Open: http://localhost:8888
```

### Option 2: Static Manifests (kubectl)

```bash
minikube start --driver=docker

# Basic deployment
k apply -f Deployment/v1.yml

# Or with more features (dev namespace, ConfigMap,)
k apply -f Deployment/v2.yml

# Or advanced (ResourceQuota, health checks, resource limits)
k apply -f Deployment/v3.yml

minikube tunnel

```

**Access the app:**

```bash

k get svc -n dev
# Open: http://<EXTERNAL-IP>
```

## Project Structure

- **webapp/** - Helm chart with ConfigMap-based configuration
- **Deployment/** - Progressive K8s manifests (v1: simple → v3: advanced with health checks & limits)
- **Dockerapp/** - Flask app source code with Dockerfile

## Cleanup

```bash
# Uninstall release
helm uninstall webapp-release
helm uninstall mywebapp-release-dev -n dev

# Pods will terminate
k get pods -n dev
```

## Troubleshooting

For help with Minikube issues, refer to the [official Minikube documentation](https://minikube.sigs.k8s.io/docs/).

Common issues:

- **Pods stuck in CrashLoopBackOff** — Check logs: `k logs <pod-name>`
- **Cannot access app** — Ensure port-forward or minikube tunnel is running
- **Image pull errors** — Build locally with `eval $(minikube docker-env)` first
