#!/bin/bash
# Create the local kind cluster used by k8s/:
# - kind cluster "devops-task"
# - cloud-provider-kind: gives Ingress and LoadBalancer services an IP
# - metrics-server: CPU metrics for the HorizontalPodAutoscaler
# Safe to run again.
set -euo pipefail

CLUSTER=devops-task
CPK_IMAGE=registry.k8s.io/cloud-provider-kind/cloud-controller-manager:v0.12.0
METRICS_URL=https://github.com/kubernetes-sigs/metrics-server/releases/download/v0.9.1/components.yaml

if ! kind get clusters | grep -qx "$CLUSTER"; then
  kind create cluster --name "$CLUSTER" --wait 120s
fi
kubectl config use-context "kind-$CLUSTER"

# runs next to the cluster on the "kind" docker network
if ! docker ps --format '{{.Names}}' | grep -qx cloud-provider-kind; then
  docker rm -f cloud-provider-kind >/dev/null 2>&1 || true
  docker run -d --name cloud-provider-kind --restart unless-stopped \
    --network kind \
    -v /var/run/docker.sock:/var/run/docker.sock \
    "$CPK_IMAGE"
fi

kubectl apply -f "$METRICS_URL"
# kind kubelets use self-signed certificates
if ! kubectl -n kube-system get deployment metrics-server \
  -o jsonpath='{.spec.template.spec.containers[0].args}' | grep -q insecure-tls; then
  kubectl -n kube-system patch deployment metrics-server --type json \
    -p '[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-insecure-tls"}]'
fi
kubectl -n kube-system rollout status deployment metrics-server --timeout 180s

echo "cluster ready: kubectl apply -k k8s/"
