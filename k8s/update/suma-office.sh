#!/usr/bin/env bash
set -euo pipefail

Service="${1:-both}"
Version="${2:-v1.0.0}"
NoCache=${NO_CACHE:-false}
BuildOnly=${BUILD_ONLY:-false}
DeployOnly=${DEPLOY_ONLY:-false}

require_cmd() { command -v "$1" >/dev/null 2>&1 || { echo "Error: $1 not found" >&2; exit 1; } }
require_cmd docker
require_cmd kubectl

root=$(dirname "${BASH_SOURCE[0]}")/..
service_root="$root/suma-office"
dockerfile="$service_root/dockerfile.api"

build_image() {
  imageName='suma-office-api'
  imageTag="$imageName:$Version"
  docker build -t "$imageTag" -f "$dockerfile" ${NoCache:+--no-cache} "$service_root"
  docker tag "$imageTag" "$imageName:latest"
}

apply_service_stack() {
  ns=$1; dir=$2; kubectl create namespace "$ns" --dry-run=client -o yaml | kubectl apply -f - || true; kubectl apply -f "$dir" || true
}

deploy_service() {
  type=$1
  if [ "$type" = "office" ]; then
    ns='suma-office'; dep='suma-office-api'; dir="$root/k8s/suma-office"
  else
    ns='suma-office-general'; dep='suma-office-general-api'; dir="$root/k8s/suma-office-general"
  fi
  apply_service_stack "$ns" "$dir"
  if [ "$DeployOnly" = false ]; then
    kubectl rollout restart deployment/$dep -n "$ns" || true
    kubectl rollout status deployment/$dep -n "$ns" --timeout=300s || true
  fi
}

if [ "$DeployOnly" = false ]; then
  echo "=== BUILD PHASE ==="
  build_image
fi
if [ "$BuildOnly" = false ]; then
  echo "=== DEPLOY PHASE ==="
  case $Service in
    office) deploy_service office;;
    general) deploy_service general;;
    both) deploy_service office; deploy_service general;;
    *) echo "Invalid service"; exit 1;;
  esac
fi

echo "=== COMPLETED ==="