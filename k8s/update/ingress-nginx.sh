#!/bin/bash
# Usage: ./ingress-nginx.sh [namespace] [k8s_folder] [output_path]
# Default: namespace="", k8s_folder="..", output_path="./ingress-yaml"

NAMESPACE="${1:-}"
K8S_FOLDER="${2:-..}"
OUTPUT_PATH="${3:-./ingress-yaml}"

set -e

# Check kubectl
if ! command -v kubectl &>/dev/null; then
  echo "kubectl tidak ditemukan. Pastikan kubectl terinstall dan dikonfigurasi." >&2
  exit 1
fi

# Create output folder if not exists
mkdir -p "$OUTPUT_PATH"

# Get ingress entries from YAML file
get_ingress_entries() {
  local file="$1"
  local entries=()
  local json
  json=$(kubectl apply --dry-run=client -f "$file" -o json 2>/dev/null || true)
  if [[ -n "$json" ]]; then
    local kind
    kind=$(echo "$json" | jq -r '.kind')
    if [[ "$kind" == "List" ]]; then
      items=$(echo "$json" | jq -c '.items[]')
    else
      items=$(echo "$json" | jq -c '.')
    fi
    while IFS= read -r item; do
      local item_kind name ns
      item_kind=$(echo "$item" | jq -r '.kind')
      name=$(echo "$item" | jq -r '.metadata.name')
      ns=$(echo "$item" | jq -r '.metadata.namespace // "default"')
      if [[ "$item_kind" == "Ingress" && -n "$name" ]]; then
        entries+=("$ns/$name|$ns|$name|$file")
      fi
    done <<< "$items"
  else
    # Fallback: grep
    if grep -q 'kind:[[:space:]]*Ingress' "$file"; then
      ns=$(grep -m1 '^ *namespace:' "$file" | awk '{print $2}')
      ns=${ns:-default}
      while read -r name; do
        name=$(echo "$name" | awk '{print $2}')
        [[ -z "$name" ]] && continue
        entries+=("$ns/$name|$ns|$name|$file")
      done < <(grep '^ *name:' "$file")
    fi
  fi
  printf '%s\n' "${entries[@]}"
}

# Find ingress YAML files
mapfile -t ingress_files < <(find "$K8S_FOLDER" -type f \( -name '*ingress*.yaml' -o -name '*ingress*.yml' \))
declare -A existing_ingress
for file in "${ingress_files[@]}"; do
  while IFS= read -r entry; do
    IFS='|' read -r key ns name f <<< "$entry"
    if [[ -n "$NAMESPACE" && "$ns" != "$NAMESPACE" ]]; then
      continue
    fi
    if [[ -n "${existing_ingress[$key]}" ]]; then
      echo "Peringatan: ingress $key didefinisikan lebih dari satu file. Menggunakan $f." >&2
    fi
    existing_ingress[$key]="$ns|$name|$f"
  done < <(get_ingress_entries "$file")
done

# Get ingress from cluster
if [[ -n "$NAMESPACE" ]]; then
  namespaces=("$NAMESPACE")
else
  mapfile -t namespaces < <(kubectl get namespaces -o json | jq -r '.items[].metadata.name')
fi
declare -A cluster_ingress
to_delete=()
for ns in "${namespaces[@]}"; do
  json=$(kubectl get ingress -n "$ns" -o json 2>/dev/null || true)
  if [[ -n "$json" ]]; then
    mapfile -t items < <(echo "$json" | jq -c '.items[]')
    for item in "${items[@]}"; do
      name=$(echo "$item" | jq -r '.metadata.name')
      key="$ns/$name"
      cluster_ingress[$key]="$ns|$name"
    done
  fi
done

to_apply=()
for key in "${!cluster_ingress[@]}"; do
  has_diff=0
  if [[ -n "${existing_ingress[$key]}" ]]; then
    IFS='|' read -r ns name file <<< "${existing_ingress[$key]}"
    kubectl diff -f "$file" --namespace "$ns" &>/dev/null || has_diff=1
    if [[ "$has_diff" == "1" ]]; then
      to_apply+=("$key|$ns|$name|$file|update")
    fi
  else
    echo "Ingress $key ada di cluster tapi tidak ada file YAML."
    IFS='|' read -r ns name <<< "${cluster_ingress[$key]}"
    to_delete+=("$key|$ns|$name")
  fi
done

for key in "${!existing_ingress[@]}"; do
  if [[ -z "${cluster_ingress[$key]}" ]]; then
    IFS='|' read -r ns name file <<< "${existing_ingress[$key]}"
    echo "File YAML untuk $key ada, tapi ingress tidak ditemukan di cluster."
    to_apply+=("$key|$ns|$name|$file|create")
  fi
done

deleted_count=0
created_count=0
updated_count=0
unchanged_count=0
skipped_count=0
error_count=0

if (( ${#to_delete[@]} > 0 )); then
  echo -e "\nMenghapus ${#to_delete[@]} ingress lama yang tidak lagi memiliki file YAML:"
  for item in "${to_delete[@]}"; do
    IFS='|' read -r key ns name <<< "$item"
    echo "Menghapus $key..."
    if kubectl delete ingress "$name" -n "$ns" --wait=true --ignore-not-found; then
      echo "  ✓ $key - berhasil dihapus"
      ((deleted_count++))
      # Wait for deletion
      for i in {1..15}; do
        kubectl get ingress "$name" -n "$ns" &>/dev/null || break
        sleep 2
      done
    else
      echo "  ✗ $key - gagal dihapus" >&2
    fi
  done
fi

if (( ${#to_apply[@]} == 0 )); then
  echo 'Tidak ada perubahan atau ingress baru untuk diterapkan.'
else
  echo -e "\nMemproses ${#to_apply[@]} ingress:"
  declare -A apply_groups
  for item in "${to_apply[@]}"; do
    IFS='|' read -r key ns name file action <<< "$item"
    apply_groups[$file]+="$key|$ns|$name|$action\n"
  done
  for file in "${!apply_groups[@]}"; do
    entries=$(echo -e "${apply_groups[$file]}")
    keys_display=$(echo "$entries" | awk -F'|' '{print $1}' | paste -sd ', ' -)
    echo "Memproses file $file untuk ingress: $keys_display"
    # Clean YAML (remove status block, last-applied annotation, generated metadata fields, empty lines)
    clean_file="$file.cleaned.yaml"
    awk 'BEGIN{skip=0} /^status:/ {skip=1} /^\S/ {if(skip){skip=0}} !skip {print}' "$file" | \
      sed -E '/^[ ]*kubectl.kubernetes.io\/last-applied-configuration:/,/^[^ ]/d' | \
      sed -E '/^[ ]*creationTimestamp:/d' | \
      sed -E '/^[ ]*generation:/d' | \
      sed -E '/^[ ]*resourceVersion:/d' | \
      sed -E '/^[ ]*uid:/d' | \
      sed '/^$/d' > "$clean_file"
    # Apply
    apply_result=$(kubectl apply -f "$clean_file" 2>&1)
    rm -f "$clean_file"
    entry_count=$(echo "$entries" | wc -l)
    entry_idx=0
    while IFS= read -r entry; do
      entry_idx=$((entry_idx+1))
      percent=$((entry_idx*100/entry_count))
      echo -ne "\rProgress: $percent% ($entry_idx/$entry_count)"
      IFS='|' read -r key ns name action <<< "$entry"
      if echo "$apply_result" | grep -q "ingress.networking.k8s.io/$name created"; then
        echo "\n  ✓ $key - berhasil dibuat"
        ((created_count++))
      elif echo "$apply_result" | grep -q "ingress.networking.k8s.io/$name configured"; then
        echo "\n  ✓ $key - berhasil diupdate"
        ((updated_count++))
      elif echo "$apply_result" | grep -q "unchanged"; then
        echo "\n  ✓ $key - tidak ada perubahan"
        ((unchanged_count++))
      elif echo "$apply_result" | grep -E -q 'already defined in ingress|already exists|spec.rules\[[0-9]+\].host: Invalid value'; then
        echo "\n  ≈ $key - dilewati karena sudah ready"
        ((skipped_count++))
      else
        echo "\n  ✗ Gagal memproses $key ($file):" >&2
        echo "$apply_result" >&2
        ((error_count++))
      fi
    done <<< "$entries"
    echo -ne "\r"
  done
fi

echo 'Deteksi ingress selesai.'
echo -e "\nRingkasan sinkronisasi ingress:"
echo "  - Dihapus   : $deleted_count"
echo "  - Dibuat    : $created_count"
echo "  - Diperbarui: $updated_count"
echo "  - Tidak berubah: $unchanged_count"
echo "  - Dilewati  : $skipped_count"
echo "  - Error     : $error_count"
