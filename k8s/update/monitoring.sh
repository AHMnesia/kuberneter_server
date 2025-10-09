#!/usr/bin/env bash
set -euo pipefail

Choice="${1:-}"
NAMESPACE="monitoring"
require_cmd() { command -v "$1" >/dev/null 2>&1 || { echo "Error: $1 not found" >&2; exit 1; } }
require_cmd kubectl
require_cmd jq || true

function ensure_namespace() { kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f - >/dev/null; }

function restart_workload() {
  kind=$1; name=$2; ns=${3:-$NAMESPACE}
  echo "- Restarting $kind/$name in namespace $ns"
  kubectl rollout restart "$kind/$name" -n "$ns" || { echo "Warning: Failed to trigger restart for $kind/$name"; return; }
  if ! kubectl rollout status "$kind/$name" -n "$ns" --timeout=180s; then
    if [ "$name" = "prometheus" ]; then
      echo "Rollout timeout on Prometheus - trying scale down/up"
      kubectl scale deployment/prometheus -n "$ns" --replicas=0 || true
      sleep 10
      kubectl scale deployment/prometheus -n "$ns" --replicas=1 || true
      kubectl get pod -n "$ns" -l app=prometheus || true
    elif [ "$name" = "grafana" ]; then
      echo "Rollout timeout on Grafana - trying scale down/up"
      kubectl scale deployment/grafana -n "$ns" --replicas=0 || true
      sleep 5
      kubectl scale deployment/grafana -n "$ns" --replicas=1 || true
      kubectl wait --for=condition=available deployment/grafana -n "$ns" --timeout=60s || true
    else
      echo "Warning: Rollout timeout for $kind/$name" >&2
    fi
  fi
}

function update_grafana_dashboards() {
  root=$(dirname "${BASH_SOURCE[0]}")/..
  dashDir="$root/monitoring/dashboards"
  if [ ! -d "$dashDir" ]; then echo "Warning: dashboards folder not found"; return; fi
  echo "Recreating grafana-dashboards ConfigMap from $dashDir"
  # build --from-file args
  args=(create configmap grafana-dashboards -n monitoring)
  while IFS= read -r -d '' f; do
    rel=${f#$dashDir/}
    key=${rel//[/__]}
    args+=(--from-file="$key=$f")
  done < <(find "$dashDir" -type f -name '*.json' -print0)
  kubectl delete configmap grafana-dashboards -n monitoring --ignore-not-found || true
  kubectl "${args[@]}" || true
}

if ! kubectl cluster-info >/dev/null 2>&1; then echo "Error: Kubernetes cluster not accessible."; exit 1; fi
ensure_namespace

if [ -z "$Choice" ]; then
  echo "Pilih tindakan:"
  echo " 1. Restart Semua Komponen Monitoring"
  echo " 2. Update JSON Dashboards (Recreate ConfigMap and Restart Grafana)"
  read -rp "Masukkan nomor (1-2): " Choice
fi
case $Choice in
  1)
    echo "Mode: Restart Semua Komponen Monitoring"
    pods=$(kubectl get pods -n monitoring -o jsonpath='{.items[*].metadata.name}') || pods=''
    if [ -n "$pods" ]; then
      for p in $pods; do kubectl delete pod "$p" -n monitoring --force --grace-period=0 || true; done
      sleep 10
    fi
    # apply manifests
    root=$(dirname "${BASH_SOURCE[0]}")/..
    mon="$root/monitoring"
    for f in rbac.yaml pvc.yaml configmap.yaml deployment.yaml service.yaml; do
      [ -f "$mon/$f" ] && kubectl apply -f "$mon/$f" || true
    done
    update_grafana_dashboards
    ;;
  2)
    echo "Mode: Update Dashboards and Restart Grafana"
    update_grafana_dashboards
    restart_workload deployment grafana monitoring
    ;;
  *) echo "Pilihan tidak valid"; exit 1;;
esac

echo "=== Done ==="