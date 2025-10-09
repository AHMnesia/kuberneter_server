#!/usr/bin/env bash
set -euo pipefail

ES_DOMAIN="${ES_DOMAIN:-search.suma-honda.local}"
ES_USER="${ES_USER:-elastic}"
ES_PASS="${ES_PASS:-admin123}"
MAX_WAIT=${MAX_WAIT:-300}
INTERVAL=${INTERVAL:-5}

echo "=== Proses: Deteksi Koneksi Elasticsearch via Domain ==="

function require_cmd() {
  command -v "$1" >/dev/null 2>&1 || { echo "Error: $1 tidak ditemukan in PATH" >&2; exit 1; }
}

require_cmd curl
# jq is optional; prefer jq but fall back to python for JSON parsing if available
HAVE_JQ=0
if command -v jq >/dev/null 2>&1; then
  HAVE_JQ=1
else
  echo "Notice: jq tidak ditemukan — akan mencoba fallback ke python untuk parsing JSON jika tersedia."
fi

wait_for_es() {
  local elapsed=0
  while [ "$elapsed" -lt "$MAX_WAIT" ]; do
    local remaining=$((MAX_WAIT - elapsed))
    echo "Coba akses Elasticsearch di https://$ES_DOMAIN/_cluster/health ... (sisa ${remaining}s)"
    status=$(curl -k -u "$ES_USER:$ES_PASS" -s -o /dev/null -w "%{http_code}" "https://$ES_DOMAIN/_cluster/health" || echo "000")
    if [ "$status" = "200" ]; then
      echo "Elasticsearch cluster health is accessible at https://$ES_DOMAIN/_cluster/health"
      return 0
    else
      echo "Belum bisa akses Elasticsearch cluster health (status: $status), tunggu dan coba lagi..."
    fi
    sleep "$INTERVAL"
    elapsed=$((elapsed + INTERVAL))
  done
  echo "Timeout: Elasticsearch cluster health is not accessible after $MAX_WAIT seconds." >&2
  return 1
}

if wait_for_es; then
  echo "=== Elasticsearch sudah siap diakses! ==="
  # check cluster health wait_for_status=yellow
  elapsed=0
  health_ok=1
  while [ "$elapsed" -lt "$MAX_WAIT" ]; do
    echo "Memeriksa _cluster/health (sisa $((MAX_WAIT - elapsed))s)..."
    out=$(curl -k -u "$ES_USER:$ES_PASS" -s "https://$ES_DOMAIN/_cluster/health?wait_for_status=yellow&timeout=1s" || true)
    if [ -n "$out" ]; then
      # normalize CRLF -> LF to make line-oriented tools reliable
      out_clean=$(printf '%s' "$out" | tr -d '\r')
      status=""
      parser_used=""
      if [ "$HAVE_JQ" -eq 1 ]; then
        status=$(printf '%s' "$out_clean" | jq -r '.status' 2>/dev/null || echo "")
        parser_used="jq"
      fi
      if [ -z "$status" ] && command -v python3 >/dev/null 2>&1; then
        status=$(printf '%s' "$out_clean" | python3 -c 'import sys,json
data=json.load(sys.stdin)
print(data.get("status",""))' 2>/dev/null || echo "")
        parser_used=${parser_used:-python3}
      fi
      if [ -z "$status" ] && command -v python >/dev/null 2>&1; then
        status=$(printf '%s' "$out_clean" | python -c 'import sys,json
data=json.load(sys.stdin)
print(data.get("status",""))' 2>/dev/null || echo "")
        parser_used=${parser_used:-python}
      fi
      if [ -z "$status" ]; then
        # try a simple grep extractor (extract "status":"value")
        parser_used=${parser_used:-grep}
        status=$(printf '%s' "$out_clean" | grep -oE '"status"\s*:\s*"[^"]+"' | head -n1 | sed -E 's/.*"status"\s*:\s*"([^"]+)"/\1/') || status=""
      fi
      if [ -z "$status" ]; then
        # sed fallback
        parser_used=${parser_used:-sed}
        status=$(printf '%s' "$out_clean" | sed -n 's/.*"status"[[:space:]]*:[[:space:]]*"\([^\"]*\)".*/\1/p' | head -n1) || status=""
      fi
      if [ -n "$status" ]; then
        echo "Cluster status: $status  (parsed with: $parser_used)"
        if [ "$status" = "yellow" ] || [ "$status" = "green" ]; then
          health_ok=0
          break
        fi
      else
        echo "Gagal parse response cluster health, menunggu..."
        # Provide a truncated debug output to help diagnose (don't dump huge bodies)
        echo "--- Debug: raw response (truncated) ---"
        if [ ${#out} -gt 1000 ]; then
          printf '%s' "${out:0:1000}"
          echo "...truncated..."
        else
          printf '%s' "$out"
        fi
        echo
        # Detect common HTML responses (proxy/login pages, etc.)
        if printf '%s' "$out" | grep -qiE '<!DOCTYPE|<html|<body'; then
          echo "Note: response looks like HTML (possible proxy, auth page, or TLS/HTTP issue)." >&2
          echo "Check that credentials, TLS settings, and the domain are correct." >&2
        fi
      fi
    else
      echo "Gagal parse response cluster health, menunggu..."
    fi
    sleep "$INTERVAL"
    elapsed=$((elapsed + INTERVAL))
  done

  if [ "$health_ok" -ne 0 ]; then
    echo "Cluster Elasticsearch belum pulih (status != yellow/green) setelah timeout. Tidak mencoba membuat user." >&2
    exit 1
  fi

  echo "Membuat user kibana_user di Elasticsearch..."
  body='{"password":"kibanapass","roles":["kibana_system"]}'
  tmpfile=$(mktemp)
  echo "$body" > "$tmpfile"
  resp=$(curl -k -u "$ES_USER:$ES_PASS" -s -X POST "https://$ES_DOMAIN/_security/user/kibana_user" -H "Content-Type: application/json" --data-binary "@$tmpfile" || true)
  echo "Response: $resp"
  if echo "$resp" | grep -q '"created":true'; then
    echo "User kibana_user berhasil dibuat di Elasticsearch."
  elif echo "$resp" | grep -q '"created":false'; then
    echo "User kibana_user sudah ada di Elasticsearch."
  else
    echo "Gagal membuat user kibana_user. Cek detail response di atas." >&2
  fi
  rm -f "$tmpfile"
else
  echo "=== Gagal akses Elasticsearch. Silakan cek konfigurasi dan jaringan. ===" >&2
  exit 1
fi
