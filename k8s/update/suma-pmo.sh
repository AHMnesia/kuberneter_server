#!/usr/bin/env bash
set -euo pipefail

NAMESPACE="${NAMESPACE:-suma-pmo}"
DEPLOYMENT_NAME="${DEPLOYMENT_NAME:-suma-pmo-api}"
IMAGE_NAME="${IMAGE_NAME:-suma-pmo-api}"
VERSION="${VERSION:-v1.0.0}"
CONTAINER_NAME="${CONTAINER_NAME:-}"

NO_CACHE_FLAG=""
[ "${NO_CACHE:-false}" = true ] && NO_CACHE_FLAG="--no-cache"

require_cmd() { command -v "$1" >/dev/null 2>&1 || { echo "Error: $1 not found" >&2; exit 1; } }
require_cmd docker
require_cmd kubectl

workspace_root=$(dirname "${BASH_SOURCE[0]}")/..
service_root="$workspace_root/suma-pmo"
dockerfile="$service_root/dockerfile"
manifests_dir="$(dirname "${BASH_SOURCE[0]}")/suma-pmo"

image_tag="$IMAGE_NAME:$VERSION"

docker build -t "$image_tag" -f "$dockerfile" $NO_CACHE_FLAG "$service_root"
docker tag "$image_tag" "$IMAGE_NAME:latest"

kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f - || true
for f in namespace.yaml service.yaml deployment.yaml hpa.yaml; do
  [ -f "$manifests_dir/$f" ] && kubectl apply -f "$manifests_dir/$f" || true
done

if [ -z "$CONTAINER_NAME" ]; then CONTAINER_NAME="$DEPLOYMENT_NAME"; fi
kubectl set image deployment/$DEPLOYMENT_NAME "$CONTAINER_NAME"="$image_tag" -n "$NAMESPACE" || true
kubectl rollout restart deployment/$DEPLOYMENT_NAME -n "$NAMESPACE" || true
kubectl rollout status deployment/$DEPLOYMENT_NAME -n "$NAMESPACE" --timeout=180s || true

echo "=== Done ==="