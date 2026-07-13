#!/usr/bin/env bash

# Exit immediately if a command exits with a non-zero status
set -e

echo "===================================================="
echo "Starting Cluster Provisioning Script"
echo "===================================================="

# Interactive Context Verification Phase
echo "--> Verifying active Kubernetes context..."

# Ensure kubectl is installed and can talk to a cluster
if ! CURRENT_CONTEXT=$(kubectl config current-context 2>/dev/null); then
  echo "❌ ERROR: Could not retrieve current kubectl context. Are you logged in?"
  exit 1
fi

echo "----------------------------------------------------"
echo "Your active Kubernetes context is:"
echo "   >> ${CURRENT_CONTEXT} <<"
echo "----------------------------------------------------"

# Prompt the user for manual confirmation
read -p "Are you sure you want to deploy to this cluster? (y/N): " response

# If the response isn't exactly y or Y, abort immediately
if [[ ! "$response" =~ ^[yY]$ ]]; then
  echo "❌ Deployment aborted by user."
  exit 0
fi

echo "Proceeding with deployment..."
echo "----------------------------------------------------"

# Create prod-mq kubernetes namespace
echo "--> Creating 'prod-mq' namespace..."
kubectl create namespace prod-mq --dry-run=client -o yaml | kubectl apply -f -

# Create ibm-licensing namespace
echo "--> Creating 'ibm-licensing' namespace..."
kubectl create namespace ibm-licensing --dry-run=client -o yaml | kubectl apply -f -

# Generate a self-signed key pair for mqa-console.example.com
echo "--> Generating self-signed TLS certificates via OpenSSL..."
WORKDIR=$(mktemp -d)
echo "Using temporary directory for cert generation: ${WORKDIR}"

openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout "${WORKDIR}/tls.key" \
  -out "${WORKDIR}/tls.crt" \
  -subj "/CN=qm1-console.example.com" \
  -addext "subjectAltName=DNS:qm1-console.example.com" \
  2>/dev/null

echo "Certificate and Private Key generated successfully."

# Create secret mq-console-tls-secret in prod-mq namespace
echo "--> Creating 'mq-console-tls-secret' in 'prod-mq' namespace..."
kubectl create secret tls mq-console-tls-secret \
  --cert="${WORKDIR}/tls.crt" \
  --key="${WORKDIR}/tls.key" \
  -n tanzu-system-ingress \
  --dry-run=client -o yaml | kubectl apply -f -

# Clean up temporary certificate files locally
rm -rf "${WORKDIR}"
echo "Temporary local certificate files cleaned up."

# Create contour gatewayclass
echo "--> Creating Contour GatewayClass..."
cat <<EOF | kubectl apply -f -
apiVersion: gateway.networking.k8s.io/v1
kind: GatewayClass
metadata:
  name: contour
spec:
  controllerName: projectcontour.io/gateway-controller
EOF

echo "===================================================="
echo "Provisioning Script Completed Successfully!"
echo "===================================================="

