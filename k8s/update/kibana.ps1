# Restart Kibana deployment only in Kubernetes

param(
    [string]$namespaceKibana = 'kibana'
)

$ErrorActionPreference = 'Stop'

if (-not (Get-Command kubectl -ErrorAction SilentlyContinue)) {
    Write-Host "ERROR: 'kubectl' not found in PATH. Install kubectl or add it to PATH before running this script." -ForegroundColor Red
    exit 1
}

Write-Host "Restarting Kibana deployment in namespace: $namespaceKibana" -ForegroundColor Yellow
kubectl rollout restart deployment/kibana -n $namespaceKibana
if ($LASTEXITCODE -ne 0) { Write-Host "Error: failed to trigger rollout restart for kibana" -ForegroundColor Red; exit 1 }
kubectl rollout status deployment/kibana -n $namespaceKibana --timeout=180s
if ($LASTEXITCODE -ne 0) { Write-Host "Warning: kubectl rollout status timed out or failed for kibana" -ForegroundColor Yellow }
Write-Host "Kibana restart complete." -ForegroundColor Green
