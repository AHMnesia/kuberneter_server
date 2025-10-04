param(
    [ValidateSet('1','2')] [string]$Choice
)

Write-Host "=== Monitoring Maintenance ===" -ForegroundColor Green

function Test-KubeAccess {
    try {
        kubectl cluster-info | Out-Null
        return $true
    } catch {
        Write-Host "Error: Kubernetes cluster not accessible." -ForegroundColor Red
        return $false
    }
}

function Ensure-NamespaceMonitoring {
    kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f - | Out-Null
}

function Restart-Workload {
    param(
        [Parameter(Mandatory)] [ValidateSet('deployment','daemonset','statefulset')] [string]$Kind,
        [Parameter(Mandatory)] [string]$Name,
        [string]$Namespace = 'monitoring'
    )
    Write-Host "- Restarting $Kind/$Name in namespace $Namespace" -ForegroundColor Yellow
    kubectl rollout restart $Kind/$Name -n $Namespace
    if ($LASTEXITCODE -ne 0) {
        Write-Host "  Warning: Failed to trigger restart for $Kind/$Name" -ForegroundColor Yellow
        return
    }
    $statusKind = $Kind
    $rolloutResult = kubectl rollout status $statusKind/$Name -n $Namespace --timeout=180s
    if ($LASTEXITCODE -ne 0) {
        if ($Name -eq 'prometheus') {
            Write-Host "  Rollout timeout pada Prometheus. Melakukan scale down ke 0 dan up ke 1 untuk recovery PVC..." -ForegroundColor Red
            kubectl scale deployment/prometheus -n $Namespace --replicas=0
            Write-Host "  Deployment Prometheus di-scale down ke 0. Menunggu sampai semua pod hilang (maks 60 detik)..." -ForegroundColor Yellow
            $timeout = 60
            $elapsed = 0
            while ($true) {
                $podsLeft = kubectl get pods -n $Namespace -l app=prometheus -o jsonpath='{.items[*].metadata.name}'
                if (-not $podsLeft) { break }
                if ($elapsed -ge $timeout) {
                    Write-Host "  Timeout: Masih ada pod Prometheus setelah 60 detik." -ForegroundColor Red
                    break
                }
                Write-Host "    Menunggu pod Prometheus hilang... ($elapsed detik)" -ForegroundColor Gray
                Start-Sleep -Seconds 5
                $elapsed += 5
            }
            kubectl scale deployment/prometheus -n $Namespace --replicas=1
            Write-Host "  Deployment Prometheus di-scale up ke 1. Menunggu sampai pod Running (maks 20 detik)..." -ForegroundColor Yellow
            $timeoutUp = 20
            $elapsedUp = 0
            while ($true) {
                $newPod = kubectl get pods -n $Namespace -l app=prometheus -o jsonpath='{.items[0].metadata.name}'
                if ($newPod) {
                    $phase = kubectl get pod $newPod -n $Namespace -o jsonpath='{.status.phase}'
                    if ($phase -eq 'Running') { break }
                }
                if ($elapsedUp -ge $timeoutUp) {
                    Write-Host "  Timeout: Pod Prometheus belum Running setelah 20 detik." -ForegroundColor Red
                    break
                }
                Write-Host "    Menunggu pod Prometheus Running... ($elapsedUp detik)" -ForegroundColor Gray
                Start-Sleep -Seconds 5
                $elapsedUp += 5
            }
            $status = kubectl get pod $newPod -n $Namespace
            Write-Host "  Status pod Prometheus setelah scale up:" -ForegroundColor Cyan
            Write-Host $status
            $logs = kubectl logs $newPod -n $Namespace --tail=30
            Write-Host "  Log pod Prometheus (tail 30):" -ForegroundColor Gray
            Write-Host $logs
        } elseif ($Name -eq 'grafana') {
            Write-Host "  Rollout timeout pada Grafana. Melakukan scale down ke 0 dan up ke 1 untuk recovery..." -ForegroundColor Red
            kubectl scale deployment/grafana -n $Namespace --replicas=0
            Write-Host "  Deployment Grafana di-scale down ke 0. Menunggu sampai semua pod hilang (maks 30 detik)..." -ForegroundColor Yellow
            $timeout = 30
            $elapsed = 0
            while ($true) {
                $podsLeft = kubectl get pods -n $Namespace -l app=grafana -o jsonpath='{.items[*].metadata.name}'
                if (-not $podsLeft) { break }
                if ($elapsed -ge $timeout) {
                    Write-Host "  Timeout: Masih ada pod Grafana setelah 30 detik." -ForegroundColor Red
                    break
                }
                Write-Host "    Menunggu pod Grafana hilang... ($elapsed detik)" -ForegroundColor Gray
                Start-Sleep -Seconds 5
                $elapsed += 5
            }
            kubectl scale deployment/grafana -n $Namespace --replicas=1
            Write-Host "  Deployment Grafana di-scale up ke 1. Menunggu sampai deployment Available / pod container ready (maks 60 detik)..." -ForegroundColor Yellow

            # Prefer kubectl wait for deployment to be available. If it fails, fall back to polling containerStatuses[].ready
            $waitOutput = kubectl wait --for=condition=available deployment/grafana -n $Namespace --timeout=60s 2>&1
            if ($LASTEXITCODE -eq 0) {
                Write-Host "  Deployment grafana became Available." -ForegroundColor Green
                $newPod = kubectl get pods -n $Namespace -l app=grafana -o jsonpath='{.items[0].metadata.name}'
            } else {
                Write-Host "  Notice: kubectl wait did not report Available: $waitOutput" -ForegroundColor Yellow
                $timeoutUp = 60
                $elapsedUp = 0
                while ($true) {
                    $newPod = kubectl get pods -n $Namespace -l app=grafana -o jsonpath='{.items[0].metadata.name}' 2>$null
                    if ($newPod) {
                        # check container ready flag (works when there is at least one container)
                        $ready = kubectl get pod $newPod -n $Namespace -o jsonpath="{.status.containerStatuses[0].ready}" 2>$null
                        if ($ready -eq 'true') { break }
                    }
                    if ($elapsedUp -ge $timeoutUp) {
                        Write-Host "  Timeout: Pod Grafana belum Ready setelah $timeoutUp detik." -ForegroundColor Red
                        break
                    }
                    Write-Host "    Menunggu pod Grafana Ready... ($elapsedUp detik)" -ForegroundColor Gray
                    Start-Sleep -Seconds 5
                    $elapsedUp += 5
                }
            }

            if ($newPod) {
                $status = kubectl get pod $newPod -n $Namespace
                Write-Host "  Status pod Grafana setelah scale up:" -ForegroundColor Cyan
                Write-Host $status
                $logs = kubectl logs $newPod -n $Namespace --tail=20
                Write-Host "  Log pod Grafana (tail 20):" -ForegroundColor Gray
                Write-Host $logs
            }
        } else {
            Write-Host "  Warning: Rollout timeout untuk $Kind/$Name. Tidak ada recovery otomatis." -ForegroundColor Yellow
        }
    }
}

function Apply-MonitoringStack {
    $root = Split-Path $PSScriptRoot -Parent
    $mon = Join-Path $root 'monitoring'
    Ensure-NamespaceMonitoring
    Write-Host "Applying monitoring manifests..." -ForegroundColor Yellow
    @(
        'rbac.yaml',
        'pvc.yaml',
        'configmap.yaml',
        'deployment.yaml',
        'service.yaml'
    ) | ForEach-Object {
        $f = Join-Path $mon $_
        if (Test-Path $f) {
            # If ServiceMonitor CRD is missing, strip ServiceMonitor docs from mixed YAML file before applying
            function Test-ServiceMonitorCRD {
                kubectl get crd servicemonitors.monitoring.coreos.com -o name > $null 2>&1
                return $LASTEXITCODE -eq 0
            }

            $hasCRD = Test-ServiceMonitorCRD
            if (-not $hasCRD) {
                $content = Get-Content -Raw -Path $f
                # split into YAML documents by lines with only '---'
                $docs = [System.Text.RegularExpressions.Regex]::Split($content, '(?m)^---\s*$')
                $filtered = $docs | Where-Object { $_ -notmatch '(?m)^\s*kind:\s*ServiceMonitor\b' }
                if ($filtered.Count -lt $docs.Count) {
                    $tmp = Join-Path $env:TEMP ("tmp-" + [guid]::NewGuid().ToString() + ".yaml")
                    ($filtered -join "`n---`n") | Out-File -FilePath $tmp -Encoding utf8
                    Write-Host "  Note: ServiceMonitor CRD not found; applying $f with ServiceMonitor documents removed" -ForegroundColor Yellow
                    kubectl apply -f $tmp
                    Remove-Item -Force $tmp
                    continue
                }
            }
            kubectl apply -f $f
        }
    }
    # After apply, (re)create grafana-dashboards ConfigMap from repo folder (do not restart grafana)
    Update-GrafanaDashboards -SourcePath $null
}

function Update-GrafanaDashboards {
    param([string]$SourcePath)
    $root = Split-Path $PSScriptRoot -Parent
    $dashDir = Join-Path (Join-Path $root 'monitoring') 'dashboards'

    if (Test-Path $dashDir) {
        Write-Host "Recreating grafana-dashboards ConfigMap from repository folder: monitoring/dashboards (recursive)" -ForegroundColor Yellow
        kubectl delete configmap grafana-dashboards -n monitoring --ignore-not-found | Out-Null
        # Use -Filter to reliably find JSON files; ensure we include files in subfolders
        $files = Get-ChildItem -Path $dashDir -Recurse -File -Filter '*.json'
        if (-not $files -or $files.Count -eq 0) {
            Write-Host "Warning: No dashboard JSON files found under: $dashDir" -ForegroundColor Yellow
            return
        }

        # Build safe --from-file=name=path args so keys are unique and derived from the file's relative path
        # This avoids collisions when different subfolders contain files with the same basename.
        $seen = @{}
        $fromFileArgs = @()
        Write-Host "Found $($files.Count) dashboard JSON files. Preparing keys for ConfigMap..." -ForegroundColor Gray
        foreach ($f in $files) {
            # compute path relative to dashboards folder
            $rel = $f.FullName.Substring($dashDir.Length).TrimStart('\','/')
            # normalize separators and create a safe key name (replace path separators with '__')
            $safeKey = ($rel -replace "[\\/]+", '__')
            # ensure key is filename-like (no leading directory separators)
            $safeKey = $safeKey -replace '\\', '__' -replace '/', '__'
            # avoid duplicates by appending a numeric suffix
            $baseKey = $safeKey
            $idx = 1
            while ($seen.ContainsKey($safeKey)) {
                $idx += 1
                $safeKey = "${baseKey}_${idx}"
            }
            $seen[$safeKey] = $true
            $fromFileArgs += "--from-file=$safeKey=$($f.FullName)"
            Write-Host "  -> Adding: $rel  as key: $safeKey" -ForegroundColor Gray
        }

        $cmdArgs = @('create','configmap','grafana-dashboards','-n','monitoring') + $fromFileArgs
        Write-Host "Creating ConfigMap grafana-dashboards with $($fromFileArgs.Count) entries..." -ForegroundColor Yellow
        & kubectl @cmdArgs
        if ($LASTEXITCODE -ne 0) {
            Write-Host "Error: Failed creating grafana-dashboards ConfigMap." -ForegroundColor Red
            return
        } else {
            Write-Host "ConfigMap grafana-dashboards berhasil dibuat dari folder dashboards (termasuk subfolder)." -ForegroundColor Green
        }

    # ConfigMap created; do not block here. Caller (choice 2) will restart Grafana immediately.
    Write-Host "ConfigMap grafana-dashboards berhasil dibuat dari folder dashboards." -ForegroundColor Green
    } else {
        Write-Host "Warning: Folder dashboards tidak ditemukan pada: $dashDir" -ForegroundColor Yellow
    }
}

if (-not (Test-KubeAccess)) { return }
Ensure-NamespaceMonitoring

# Run main flow in try/catch/finally so we always print Done and surface errors
try {
    Write-Host "Pilih tindakan:" -ForegroundColor Yellow
    Write-Host "  1. Restart Semua Komponen Monitoring (Redeploy Full Stack)" -ForegroundColor Gray
    Write-Host "  2. Update JSON Dashboards (Recreate ConfigMap and Restart Grafana)" -ForegroundColor Gray

    if (-not $Choice) {
        $Choice = Read-Host "Masukkan nomor (1-2)"
    }

    switch ($Choice) {
        '1' {
            Write-Host "Mode: Restart Semua Komponen Monitoring" -ForegroundColor Green
            # Force delete semua pod di namespace monitoring sebelum apply ulang
            $allPods = kubectl get pods -n monitoring -o jsonpath='{.items[*].metadata.name}'
            if ($allPods) {
                Write-Host "Force delete semua pod di namespace monitoring..." -ForegroundColor Red
                $allPodsArr = $allPods -split ' '
                foreach ($p in $allPodsArr) {
                    kubectl delete pod $p -n monitoring --force --grace-period=0
                    Write-Host "  Pod $p dihapus paksa." -ForegroundColor Yellow
                }
                Write-Host "Menunggu 10 detik setelah force delete semua pod..." -ForegroundColor Yellow
                Start-Sleep -Seconds 10
            }
            Apply-MonitoringStack
        }
        '2' {
            Write-Host "Mode: Update Dashboards and Restart Grafana" -ForegroundColor Green
            Update-GrafanaDashboards -SourcePath $null
            Write-Host "Restarting Grafana deployment to pick up new dashboards..." -ForegroundColor Yellow
            Restart-Workload -Kind 'deployment' -Name 'grafana' -Namespace 'monitoring'
        }
        default {
            Write-Host "Pilihan tidak valid. Keluar." -ForegroundColor Yellow
            return
        }
    }

} catch {
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
    if ($_.Exception.InnerException) { Write-Host "Inner: $($_.Exception.InnerException.Message)" -ForegroundColor Red }
} finally {
    Write-Host "=== Done ===" -ForegroundColor Green
}