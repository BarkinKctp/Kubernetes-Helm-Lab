# AWS EKS Deployment Guide

Deploy Flask webapp to AWS EKS (Elastic Kubernetes Service) in production.

## Prerequisites

- AWS Account with IAM user
- eksctl, kubectl, Docker, AWS CLI installed

## 1. IAM Permissions Setup

**Option A: Managed Policies (recommended)**

```bash
aws iam attach-user-policy --user-name <IAM_USER> --policy-arn arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryPowerUser
aws iam attach-user-policy --user-name <IAM_USER> --policy-arn arn:aws:iam::aws:policy/AmazonECS_FullAccess
```

**Option B: Manual Setup (if managed policies fail)**
Navigate to: **IAM → Users → <IAM_USER> → Add permissions → Create inline policy**

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

**Wait 10-15 minutes** — CloudFormation provisions infrastructure and configures the kubeconfig file.

Update the kubeconfig:

```bash
eksctl utils write-kubeconfig --cluster=webapp-prod --region=eu-west-1 --set-kubeconfig-context=true
kubectl get nodes
```

## 6. Configure Node IAM Permissions

Allow nodes to pull images from ECR:

```bash
aws iam list-roles --query 'Roles[?contains(RoleName, `webapp-prod`)].RoleName'
aws iam attach-role-policy --role-name <ROLE_NAME> --policy-arn arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly
```

**Or via AWS Console:** IAM → Roles → Search "NodeInstanceRole" → Find webapp-prod role → Copy exact name.

**Note:** Without this IAM policy, nodes cannot pull images from ECR, resulting in ImagePullBackOff errors.

## 7. Deploy with Helm

Deploy the Flask application to the EKS cluster with production settings.

```bash
# Create prod namespace (isolated environment)
kubectl create namespace prod

# Deploy Helm chart with production values
# Replace <ACCOUNT_ID> with your AWS account ID
helm install webapp-prod helm-webapp/ \
  --values helm-webapp/values.yaml \
  -f helm-webapp/values-prod.yaml \
  --set image.repository=<ACCOUNT_ID>.dkr.ecr.eu-west-1.amazonaws.com/helm-aws-webapp \
  --namespace prod \
  --create-namespace

# Verify all pods are running
kubectl get pods -n prod
# Should show: webapp-prod-xxxxx  1/1  Running

# Verify service and get LoadBalancer IP
kubectl get svc -n prod
# EXTERNAL-IP column shows the ELB DNS name (takes ~2 min to provision)
```

**What gets deployed:**

- 3 replicas (HA)
- Auto-scaling (3-10 pods)
- AWS LoadBalancer
- Resource limits
- Environment ConfigMap

## 8. Access Application

```bash
# Option A: Via LoadBalancer (~2 min for provisioning)
kubectl get svc -n prod --watch

# Option B: Immediate port-forward
kubectl port-forward svc/webapp-prod 8888:80 -n prod
# Open: http://localhost:8888
```

## Cleanup

```bash
helm uninstall webapp-prod -n prod
kubectl delete namespace prod
eksctl delete cluster --name webapp-prod --region eu-west-1
```

## Switching Between Contexts (Minikube ↔ AWS EKS)

The kubeconfig file stores **multiple Kubernetes clusters**. It is easy to switch between local development (Minikube) and production (EKS):

```bash
kubectl config get-contexts       # List all
kubectl config use-context minikube
kubectl config use-context <account-id>@webapp-prod.eu-west-1.eksctl.io
```

## Troubleshooting

### Cluster Creation Issues

- **Stack stuck (>20 min)** → `eksctl get cluster --region eu-west-1` and check AWS CloudFormation console
- **Insufficient IAM permissions** → Verify Step 1 policies attached
- **VPC/Subnet issues** → Check AWS VPC console

### Node & ECR Issues (Step 6)

- **ImagePullBackOff** → Run Step 6 IAM attachment again
- **Cannot find node role** → `eksctl get nodegroup --cluster webapp-prod --region eu-west-1 -o json | grep NodeInstanceRoleArn`

### Helm Deployment Issues

- **Pod stuck in Pending** → `kubectl describe pod <pod-name> -n prod`
- **CrashLoopBackOff** → `kubectl logs <pod-name> -n prod`
- **PENDING external IP** → Wait 2-3 min

### General Debugging

```bash
kubectl cluster-info
kubectl get all -n prod
kubectl describe node <node-name>
kubectl get events -n prod --sort-by='.lastTimestamp'
```

### Cost

EKS ~$0.10/hr + nodes ~$0.08/hr + ELB ~$0.025/hr. Delete when done.
