#!/bin/bash
set -euo pipefail

if [ -z "${GITHUB_TOKEN:-}" ]; then
  if ! gh auth status &>/dev/null; then
    gh auth login
  fi
  GITHUB_TOKEN=$(gh auth token)
fi

GITHUB_TOKEN=$(gh auth token)

echo "── Reading Terraform outputs ──"
cd infra || { echo "Error: infra directory not found"; exit 1; }
CLUSTER_NAME=$(terraform output -raw cluster_name) || { echo "Error: Unable to read cluster_name from Terraform"; exit 1; }
ECR_URL=$(terraform output -raw ecr_url) || { echo "Error: Unable to read ecr_url from Terraform"; exit 1; }
GHA_ROLE_ARN=$(terraform output -raw gha_role_arn) || { echo "Error: Unable to read gha_role_arn from Terraform"; exit 1; }
ACCOUNT_ID=$(terraform output -raw account_id) || { echo "Error: Unable to read account_id from Terraform"; exit 1; }
REGION=$(terraform output -raw region) || { echo "Error: Unable to read region from Terraform"; exit 1; }
GITHUB_ORG=$(terraform output -raw github_org) || { echo "Error: Unable to read github_org from Terraform"; exit 1; }
GITHUB_REPO=$(terraform output -raw github_repo) || { echo "Error: Unable to read github_repo from Terraform"; exit 1; }
cd .. || exit 1

echo "── Updating kubeconfig for EKS ──"
aws eks update-kubeconfig \
  --name "$CLUSTER_NAME" \
  --region "$REGION" || { echo "Error: Failed to update kubeconfig"; exit 1; }

echo "── Installing ArgoCD ──"
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f - || { echo "Error: Failed to create argocd namespace"; exit 1; }
kubectl apply -n argocd \
  -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml || { echo "Error: Failed to install ArgoCD"; exit 1; }

echo "── Waiting for ArgoCD server ──"
kubectl wait deployment argocd-server \
  -n argocd \
  --for=condition=Available \
  --timeout=300s

echo "── Exposing ArgoCD via LoadBalancer ──"
kubectl patch svc argocd-server -n argocd \
  -p '{"spec": {"type": "LoadBalancer"}}'

echo "── Waiting for ELB hostname ──"
ARGOCD_HOST=""
while [ -z "$ARGOCD_HOST" ]; do
  ARGOCD_HOST=$(kubectl get svc argocd-server -n argocd \
    -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || true)
  [ -z "$ARGOCD_HOST" ] && echo "  still waiting..." && sleep 10
done
echo "  ArgoCD: https://$ARGOCD_HOST"

echo "── Configuring Dex (GHA OIDC) ──"
kubectl patch configmap argocd-cm -n argocd --patch "
data:
  url: https://$ARGOCD_HOST
  dex.config: |
    connectors:
      - type: oidc
        id: github-actions
        name: GitHub Actions
        config:
          issuer: https://token.actions.githubusercontent.com/
          scopes: [openid]
          userNameKey: sub
          insecureSkipEmailVerified: true
"

echo "── Configuring RBAC ──"
kubectl patch configmap argocd-rbac-cm -n argocd --patch "
data:
  policy.csv: |
    p, repo:$GITHUB_ORG/$GITHUB_REPO:ref:refs/heads/main, applications, sync,   default/webapp-prod, allow
    p, repo:$GITHUB_ORG/$GITHUB_REPO:ref:refs/heads/main, applications, get,    default/webapp-prod, allow
    p, repo:$GITHUB_ORG/$GITHUB_REPO:ref:refs/heads/main, applications, update, default/webapp-prod, allow
  policy.default: role:readonly
"

kubectl rollout restart deployment argocd-dex-server -n argocd
kubectl rollout status  deployment argocd-dex-server -n argocd --timeout=120s

echo "── Getting ArgoCD admin password ──"
ARGOCD_PASSWORD=$(kubectl get secret argocd-initial-admin-secret \
  -n argocd \
  -o jsonpath='{.data.password}' | base64 -d) || { echo "Error: Failed to retrieve ArgoCD password"; exit 1; }

echo "── Logging into ArgoCD CLI ──"
argocd login "$ARGOCD_HOST" \
  --username admin \
  --password "$ARGOCD_PASSWORD" \
  --insecure \
  --grpc-web || { echo "Error: Failed to login to ArgoCD"; exit 1; }

echo "── Saving credentials (remove after login) ──"
echo "ArgoCD URL: https://$ARGOCD_HOST" > /tmp/argocd-creds.txt
echo "Username: admin" >> /tmp/argocd-creds.txt
echo "Password: $ARGOCD_PASSWORD" >> /tmp/argocd-creds.txt
chmod 600 /tmp/argocd-creds.txt
echo "Credentials saved to: /tmp/argocd-creds.txt"
unset ARGOCD_PASSWORD

echo "── Creating ArgoCD app (helm-webapp) ──"
if [ ! -d "helm-webapp" ]; then
  echo "Error: helm-webapp directory not found"
  exit 1
fi

argocd app create webapp-prod \
  --repo "https://github.com/$GITHUB_ORG/$GITHUB_REPO" \
  --path helm-webapp \
  --dest-server https://kubernetes.default.svc \
  --dest-namespace prod \
  --helm-set "image.repository=$ECR_URL" \
  --values values.yaml \
  --values values-prod.yaml \
  --sync-policy automated \
  --auto-prune \
  --self-heal \
  --upsert || { echo "Error: Failed to create ArgoCD app"; exit 1; }

echo "── Registering GitHub webhook ──"
EXISTING=$(curl -sSf \
  -H "Authorization: token $GITHUB_TOKEN" \
  -H "Accept: application/vnd.github.v3+json" \
  "https://api.github.com/repos/$GITHUB_ORG/$GITHUB_REPO/hooks" \
  | jq "[.[] | select(.config.url | contains(\"$ARGOCD_HOST\"))] | length") || { echo "Error: Failed to check existing webhooks"; exit 1; }

if [ "$EXISTING" -gt 0 ]; then
  echo "  webhook already registered, skipping"
else
  curl -sSf -X POST \
    -H "Authorization: token $GITHUB_TOKEN" \
    -H "Accept: application/vnd.github.v3+json" \
    "https://api.github.com/repos/$GITHUB_ORG/$GITHUB_REPO/hooks" \
    -d "{
      \"name\": \"web\",
      \"active\": true,
      \"events\": [\"push\"],
      \"config\": {
        \"url\": \"https://$ARGOCD_HOST/api/webhook\",
        \"content_type\": \"json\",
        \"insecure_ssl\": \"1\"
      }
    }" | jq .id || { echo "Error: Failed to register webhook"; exit 1; }
  echo "  webhook registered"
fi

echo "── Setting GitHub Actions secrets ──"
# requires gh CLI logged in
gh secret set AWS_ACCOUNT_ID --body "$ACCOUNT_ID"   --repo "$GITHUB_ORG/$GITHUB_REPO"
gh secret set GHA_ROLE_ARN   --body "$GHA_ROLE_ARN" --repo "$GITHUB_ORG/$GITHUB_REPO"
gh secret set ARGOCD_SERVER  --body "$ARGOCD_HOST"  --repo "$GITHUB_ORG/$GITHUB_REPO"

echo ""
echo "   Done."
echo "   ArgoCD UI    : https://$ARGOCD_HOST"
echo "   Credentials  : /tmp/argocd-creds.txt"
echo "   ECR          : $ECR_URL"