#!/usr/bin/env bash
set -euo pipefail

NAMESPACE="${NAMESPACE:-kibana}"
require_cmd() { command -v "$1" >/dev/null 2>&1 || { echo "Error: $1 not found" >&2; exit 1; } }
require_cmd kubectl

echo "Restarting Kibana deployment in namespace: $NAMESPACE"
kubectl rollout restart deployment/kibana -n "$NAMESPACE"
if ! kubectl rollout status deployment/kibana -n "$NAMESPACE" --timeout=180s; then
  echo "Warning: kubectl rollout status timed out or failed for kibana" >&2
fi
echo "Kibana restart complete."