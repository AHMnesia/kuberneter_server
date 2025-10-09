#!/usr/bin/env bash
set -euo pipefail

NAMESPACE="${NAMESPACE:-suma-chat}"
VERSION="${VERSION:-v1.0.0}"
NO_CACHE=${NO_CACHE:-false}
BUILD_ONLY=${BUILD_ONLY:-false}
DEPLOY_ONLY=${DEPLOY_ONLY:-false}
DRY_RUN=${DRY_RUN:-false}
SKIP_ROLLOUT_STATUS=${SKIP_ROLLOUT_STATUS:-false}

KUBECTL="${KUBECTL:-kubectl}"
DOCKER="${DOCKER:-docker}"

require_cmd() { command -v "$1" >/dev/null 2>&1 || { echo "Error: $1 not found" >&2; exit 1; } }
require_cmd "$KUBECTL"
require_cmd "$DOCKER"

root=$(dirname "${BASH_SOURCE[0]}")/..
service_root="$root/suma-chat"
dockerfile="$service_root/dockerfile"
manifests_root="$root/suma-chat"

image_name="suma-chat"
image_tag="$image_name:$VERSION"

if [ "$BUILD_ONLY" = true ] && [ "$DEPLOY_ONLY" = true ]; then echo "BuildOnly and DeployOnly cannot be used together"; exit 1; fi

build_image() {
  if [ "$DRY_RUN" = true ]; then echo "[DRY-RUN] docker build -t $image_tag -f $dockerfile $service_root"; return; fi
  docker build -t "$image_tag" -f "$dockerfile" ${NO_CACHE:+--no-cache} "$service_root"
  docker tag "$image_tag" "$image_name:latest"
}

deploy_manifests() {
  [ -f "$manifests_root/namespace.yaml" ] && kubectl apply -f "$manifests_root/namespace.yaml"
  for f in "$manifests_root"/*.yaml; do
    [ -f "$f" ] || continue
    kubectl apply -f "$f" -n "$NAMESPACE"
  done
}

if [ "$DRY_RUN" = true ]; then echo "DRY-RUN mode"; fi

if [ "$DEPLOY_ONLY" = false ]; then
  echo "=== BUILD PHASE ==="
  build_image
fi

if [ "$BUILD_ONLY" = false ]; then
  echo "=== DEPLOY PHASE ==="
  deploy_manifests
  if [ "$DEPLOY_ONLY" = false ]; then
    kubectl rollout restart deployment/suma-chat -n "$NAMESPACE" || true
  fi
  if [ "$SKIP_ROLLOUT_STATUS" = false ]; then
    kubectl rollout status deployment/suma-chat -n "$NAMESPACE" --timeout=180s || true
  fi
  kubectl get pods -n "$NAMESPACE" -o wide || true
fi

echo "=== COMPLETED ==="
