#!/usr/bin/env bash
set -euo pipefail

SSL_ROOT="${SSL_ROOT:-/c/docker/ssl}"
KUBECTL="${KUBECTL:-kubectl}"

require_cmd() { command -v "$1" >/dev/null 2>&1 || { echo "Error: $1 not found" >&2; exit 1; } }
require_cmd kubectl
require_cmd jq || true

echo "====================================="
echo "       SSL MANAGER (bash)"
echo "====================================="

echo "1) Update SSL Manual (dari folder ssl/)"
echo "2) Update ke Auto SSL (cert-manager)"
echo "3) Cek Status SSL Semua Domain"
echo "4) Keluar"
read -rp "Pilih menu (1-4): " CHOICE

get_domain_folders() {
  local path="$1"
  [ -d "$path" ] || { echo "Folder $path tidak ada" >&2; return; }
  for d in "$path"/*; do
    [ -d "$d" ] || continue
    base=$(basename "$d")
    if [[ "$base" =~ ^[a-zA-Z0-9.-]+$ ]]; then
      echo "$base"
    fi
  done
}

get_all_ingress_domains() {
  kubectl get ingress --all-namespaces -o json 2>/dev/null | jq -r '.items[] | .spec.tls[]?.hosts[]?, .spec.rules[]?.host? ' | sort -u || true
}

update_manual_ssl() {
  local domains=("$@")
  echo "Domain yang akan diupdate: ${domains[*]}"
  read -rp "Lanjutkan update SSL manual? (y/N): " ans
  if [[ ! "$ans" =~ ^[Yy] ]]; then echo "Batal"; return; fi
  for domain in "${domains[@]}"; do
    echo "Processing domain: $domain"
    crt="$SSL_ROOT/$domain/certificate.crt"
    key="$SSL_ROOT/$domain/certificate.key"
    if [ ! -f "$crt" ] || [ ! -f "$key" ]; then echo "  ERROR: Certificate files not found for $domain"; continue; fi
    # find ingresses that reference the domain
    ingresses=$(kubectl get ingress --all-namespaces -o json | jq -r '.items[] | select((.spec.tls[]?.hosts[]? == "'"$domain"'") or (.spec.rules[]?.host? == "'"$domain"'")) | "\(.metadata.namespace)/\(.metadata.name) @\(.spec.tls[]?.secretName // empty)"' )
    while read -r line; do
      [[ -z "$line" ]] && continue
      ns=${line%%/*}
      rest=${line#*/}
      name=${rest%% @*}
      secretName=${rest#* @}
      if [ "$secretName" = "$rest" ]; then secretName=""; fi
      if [ -z "$secretName" ]; secretName="tls-$domain"; fi
      echo "  Updating secret $secretName in namespace $ns"
      kubectl create secret tls "$secretName" --cert="$crt" --key="$key" -n "$ns" --dry-run=client -o yaml | kubectl apply -f -
      echo "  Restarting ingress controller (ingress-nginx)"
      kubectl rollout restart deployment/ingress-nginx-controller -n ingress-nginx || true
    done <<< "$ingresses"
  done
}

update_auto_ssl() {
  local domains=("$@")
  echo "Enable cert-manager for domains: ${domains[*]}"
  read -rp "Lanjutkan update ke auto SSL? (y/N): " ans
  if [[ ! "$ans" =~ ^[Yy] ]]; then echo "Batal"; return; fi
  for domain in "${domains[@]}"; do
    ingresses=$(kubectl get ingress --all-namespaces -o json | jq -r '.items[] | select((.spec.tls[]?.hosts[]? == "'"$domain"'") or (.spec.rules[]?.host? == "'"$domain"'")) | "\(.metadata.namespace)/\(.metadata.name) @\(.spec.tls[]?.secretName // empty)"')
    while read -r line; do
      [[ -z "$line" ]] && continue
      ns=${line%%/*}
      rest=${line#*/}
      name=${rest%% @*}
      secretName=${rest#* @}
      if [ "$secretName" = "$rest" ]; then secretName=""; fi
      if [ -z "$secretName" ]; secretName="tls-$domain"; fi
      echo "  Enable cert-manager on ingress $name in $ns"
      kubectl delete secret "$secretName" -n "$ns" --ignore-not-found || true
      kubectl annotate ingress "$name" -n "$ns" cert-manager.io/cluster-issuer=selfsigned-cluster-issuer --overwrite || true
    done <<< "$ingresses"
  done
}

case $CHOICE in
  1)
    domains=( $(get_domain_folders "$SSL_ROOT") )
    if [ ${#domains[@]} -eq 0 ]; then echo "No domain folders found"; exit 0; fi
    echo "Pilih domain(s):"
    select d in "${domains[@]}" "Semua" "Keluar"; do
      if [ "$d" = "Semua" ]; then update_manual_ssl "${domains[@]}"; break; fi
      if [ "$d" = "Keluar" ]; then exit 0; fi
      update_manual_ssl "$d"; break
    done
    ;;
  2)
    domains=( $(get_all_ingress_domains) )
    if [ ${#domains[@]} -eq 0 ]; then echo "No ingress domains found"; exit 0; fi
    echo "Pilih domain(s):"
    select d in "${domains[@]}" "Semua" "Keluar"; do
      if [ "$d" = "Semua" ]; then update_auto_ssl "${domains[@]}"; break; fi
      if [ "$d" = "Keluar" ]; then exit 0; fi
      update_auto_ssl "$d"; break
    done
    ;;
  3)
    kubectl get ingress --all-namespaces -o json | jq -r '.items[] | .metadata.namespace + "/" + .metadata.name + " -> " + ( [.spec.tls[]?.hosts[]?] | join(",") )'
    ;;
  4) exit 0;;
  *) echo "Invalid"; exit 1;;
esac
