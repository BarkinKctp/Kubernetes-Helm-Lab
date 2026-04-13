# AWS EKS Deployment Guide

Deploy Flask webapp to AWS EKS (Elastic Kubernetes Service) in production.

## Prerequisites

- AWS Account with IAM user (e.g., `Terraform`)
- eksctl, kubectl, Docker, AWS CLI installed

## 1. IAM Permissions Setup

**Option A: Managed Policies (recommended)**

```bash
aws iam attach-user-policy --user-name Terraform --policy-arn arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryPowerUser
aws iam attach-user-policy --user-name Terraform --policy-arn arn:aws:iam::aws:policy/AmazonECS_FullAccess
```

**Option B: Manual Setup (if managed policies fail)**
Go to: **IAM → Users → Terraform → Add permissions → Create inline policy**

Add all permissions for: EKS, EC2, IAM, CloudFormation, ECR, autoscaling, logs

## 2. ECR Setup

```bash
# Login to ECR
aws ecr get-login-password --region eu-west-1 | docker login --username AWS --password-stdin <ACCOUNT_ID>.dkr.ecr.eu-west-1.amazonaws.com

# Create repository
aws ecr create-repository --repository-name helm-aws-webapp --region eu-west-1
```

## 3. Build & Push Docker Image

```bash
# Build image
docker build -t helm-aws-webapp ./Dockerapp

# Tag for ECR
docker tag helm-aws-webapp:latest <ACCOUNT_ID>.dkr.ecr.eu-west-1.amazonaws.com/helm-aws-webapp:latest

# Push to ECR
docker push <ACCOUNT_ID>.dkr.ecr.eu-west-1.amazonaws.com/helm-aws-webapp:latest
```

## 4. Install eksctl

```bash
# Windows (PowerShell)
choco install eksctl

# macOS
brew install eksctl

# Linux
curl --silent --location "https://github.com/weaveworks/eksctl/releases/latest/download/eksctl_$(uname -s)_amd64.tar.gz" | tar xz -C /tmp
sudo mv /tmp/eksctl /usr/local/bin
```

## 5. Create EKS Cluster

```bash
eksctl create cluster \
  --name webapp-prod \
  --region eu-west-1 \
  --nodegroup-name webapp-nodes \
  --node-type t3.medium \
  --nodes 2 \
  --nodes-min 2 \
  --nodes-max 5 \
  --managed
```

**Wait 10-15 minutes** — CloudFormation creates VPC, subnets, security groups, auto-scaling groups, kubeconfig auto-configured.

Verify cluster:

```bash
kubectl get nodes
```

## 6. Configure Node IAM Permissions

```bash
# Attach ECR read permission to node instance role
aws iam attach-role-policy \
  --role-name eksctl-webapp-prod-nodegroup-webapp-nodes-NodeInstanceRole-XXXXX \
  --policy-arn arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly
```

**Find actual role name:**

```bash
eksctl get nodegroup --cluster webapp-prod --region eu-west-1
```

## 7. Deploy with Helm

```bash
# Create prod namespace
kubectl create namespace prod

# Deploy with prod values
helm install webapp-prod helm-webapp/ \
  --values helm-webapp/values.yaml \
  -f helm-webapp/values-prod.yaml \
  --namespace prod \
  --create-namespace

# Verify deployment
kubectl get svc -n prod
# EXTERNAL-IP will be the ELB DNS name — takes ~2 min to provision
```

## 8. Access Application

```bash
# Option A: Wait for LoadBalancer to provision, then use EXTERNAL-IP
kubectl get svc -n prod --watch

# Option B: Port forward immediately
kubectl port-forward svc/webapp-prod 8888:80 -n prod
# Open: http://localhost:8888
```

## Cleanup

```bash
# Uninstall Helm release
helm uninstall webapp-prod -n prod

# Delete EKS cluster (takes ~15 minutes)
eksctl delete cluster --name webapp-prod --region eu-west-1
# Deletes: VPC, subnets, security groups, ELB, auto-scaling groups
```

## Production Best Practices Applied

**3 replicas** — High availability (odd number)
**HPA enabled** (3-10 replicas) — Auto-scales based on CPU
**LoadBalancer service** — Production-grade ingress
**Resource limits** — Prevents resource starvation
 **t3.medium nodes** — Cost-efficient, sufficient for web app
 **Auto-scaling group** (min 2, max 5) — Handles traffic spikes

## Troubleshooting

- **AccessDenied on ECR** → Verify IAM user has ecr:GetAuthorizationToken
- **Nodes not pulling images** → Check node role has AmazonEC2ContainerRegistryReadOnly
- **PENDING service** → Wait for ELB provisioning (~2 min)
- **Pod CrashLoopBackOff** → `kubectl logs <pod-name> -n prod`
- **Cluster creation failed** → Check AWS console CloudFormation for stack errors
