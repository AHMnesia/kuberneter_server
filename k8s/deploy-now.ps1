param(
    [string]$VERSION = 'v1.0.0'
)

# Menu: Pilih service yang ingin dideploy
$services = @(
    @{ Name = 'Suma Ecommerce'; RepoPath = 'suma-ecommerce'; K8sPath = 'suma-ecommerce'; Image = 'suma-ecommerce-api'; Dockerfile = 'dockerfile' },
    @{ Name = 'Suma Office'; RepoPath = 'suma-office'; K8sPath = 'suma-office'; Image = 'suma-office-api'; Dockerfile = 'dockerfile.api' },
    @{ Name = 'Suma Office General'; RepoPath = 'suma-office'; K8sPath = 'suma-office-general'; Image = 'suma-office-general-api'; Dockerfile = 'dockerfile.api' },
    @{ Name = 'Suma Android'; RepoPath = 'suma-android'; K8sPath = 'suma-android'; Image = 'suma-android-api'; Dockerfile = 'dockerfile' },
    @{ Name = 'Suma PMO'; RepoPath = 'suma-pmo'; K8sPath = 'suma-pmo'; Image = 'suma-pmo-api'; Dockerfile = 'dockerfile' },
    @{ Name = 'Suma Chat'; RepoPath = 'suma-chat'; K8sPath = 'suma-chat'; Image = 'suma-chat'; Dockerfile = 'dockerfile' }
)

Write-Host '=== Pilih Service yang akan dideploy ===' -ForegroundColor Cyan
for ($i=0; $i -lt $services.Count; $i++) {
    Write-Host ("[$i] {0}" -f $services[$i].Name) -ForegroundColor Yellow
}

$selected = Read-Host 'Masukkan nomor service yang ingin dideploy (pisahkan dengan koma, contoh: 0,2,3)'
$selectedIdx = $selected -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ -match '^\d+$' }

# Deploy Infrastruktur (selalu otomatis)
Write-Host '=== Deploy Infrastruktur (Otomatis) ===' -ForegroundColor Green

$root = Split-Path $PSScriptRoot -Parent
Set-Location $PSScriptRoot

# 1. Vendor components (cert-manager, ingress-nginx, metrics-server)
$vendorsDir = Join-Path $PSScriptRoot 'vendors'
if (Test-Path $vendorsDir) {
    Write-Host 'Menemukan folder vendors/. Memastikan komponen vendor terinstall...' -ForegroundColor Cyan

    $helmValues = Join-Path $vendorsDir 'helm-values.yaml'
    $helmCmd = Get-Command helm -ErrorAction SilentlyContinue

    if ($helmCmd) {
        try {
            helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx | Out-Null
            helm repo update | Out-Null
            kubectl create namespace ingress-nginx --dry-run=client -o yaml | kubectl apply -f - | Out-Null
            if (Test-Path $helmValues) {
                Write-Host 'Deploying ingress-nginx melalui Helm dengan values khusus...' -ForegroundColor Cyan
                helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx --namespace ingress-nginx -f $helmValues
            } else {
                Write-Host 'helm-values.yaml tidak ditemukan. Menggunakan default chart ingress-nginx...' -ForegroundColor Yellow
                helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx --namespace ingress-nginx
            }
            Write-Host 'Ingress-nginx dipasang melalui Helm.' -ForegroundColor Green
        } catch {
            Write-Host ('Warning: instalasi Helm gagal ({0}). Menggunakan fallback kubectl apply vendors/.' -f $_.Exception.Message) -ForegroundColor Yellow
            try { kubectl apply -f $vendorsDir --recursive } catch { Write-Host 'Warning: kubectl apply vendors gagal.' -ForegroundColor Yellow }
        }
    } else {
        Write-Host 'Helm tidak ditemukan. Menggunakan kubectl apply pada vendors/.' -ForegroundColor Yellow
        try { kubectl apply -f $vendorsDir --recursive } catch { Write-Host 'Warning: kubectl apply vendors gagal.' -ForegroundColor Yellow }
    }

    $certManagerFile = Join-Path $vendorsDir 'cert-manager.yaml'
    if (Test-Path $certManagerFile) {
        Write-Host 'Mengapply cert-manager.yaml dari vendors/...' -ForegroundColor Cyan
        try { kubectl apply -f $certManagerFile } catch { Write-Host ('Warning: gagal apply cert-manager.yaml ({0})' -f $_.Exception.Message) -ForegroundColor Yellow }
    }

    $metricsServerFile = Join-Path $vendorsDir 'metrics-server.yaml'
    if (Test-Path $metricsServerFile) {
        Write-Host 'Mengapply metrics-server.yaml dari vendors/...' -ForegroundColor Cyan
        try { kubectl apply -f $metricsServerFile } catch { Write-Host ('Warning: gagal apply metrics-server.yaml ({0})' -f $_.Exception.Message) -ForegroundColor Yellow }
    }

    if (Test-Path $certManagerFile) {
        Write-Host 'Menunggu webhook cert-manager siap (timeout 120s)...' -ForegroundColor Yellow
        $cmTimeout = 120
        $elapsed = 0
        $cmReady = $false
        while ($elapsed -lt $cmTimeout) {
            try {
                $cmPods = kubectl get pods -n cert-manager --field-selector=status.phase=Running -o jsonpath='{.items[*].metadata.name}' 2>$null
                if ($cmPods) {
                    $webhookEp = kubectl get endpoints cert-manager-webhook -n cert-manager --ignore-not-found -o jsonpath='{.subsets[*].addresses[*].ip}' 2>$null
                    if ($webhookEp) { $cmReady = $true; break }
                }
            } catch { }
            Start-Sleep -Seconds 5
            $elapsed += 5
        }
        if ($cmReady) { Write-Host 'cert-manager webhook siap.' -ForegroundColor Green } else { Write-Host 'WARNING: cert-manager webhook belum siap setelah 120s.' -ForegroundColor Yellow }
    }

    Write-Host 'Menginstall Prometheus Operator CRDs...' -ForegroundColor Cyan
    $crdUrls = @(
        'https://raw.githubusercontent.com/prometheus-operator/prometheus-operator/main/example/prometheus-operator-crd/monitoring.coreos.com_servicemonitors.yaml',
        'https://raw.githubusercontent.com/prometheus-operator/prometheus-operator/main/example/prometheus-operator-crd/monitoring.coreos.com_prometheusrules.yaml',
        'https://raw.githubusercontent.com/prometheus-operator/prometheus-operator/main/example/prometheus-operator-crd/monitoring.coreos.com_podmonitors.yaml',
        'https://raw.githubusercontent.com/prometheus-operator/prometheus-operator/main/example/prometheus-operator-crd/monitoring.coreos.com_prometheuses.yaml',
        'https://raw.githubusercontent.com/prometheus-operator/prometheus-operator/main/example/prometheus-operator-crd/monitoring.coreos.com_alertmanagers.yaml'
    )
    foreach ($crd in $crdUrls) {
        try { kubectl apply -f $crd | Out-Null } catch { Write-Host ('Warning: gagal apply {0}' -f $crd) -ForegroundColor Yellow }
    }

    Write-Host 'Menunggu ingress-nginx-controller available (timeout 180s)...' -ForegroundColor Yellow
    try {
        kubectl wait --for=condition=Available deployment/ingress-nginx-controller -n ingress-nginx --timeout=180s | Out-Null
    } catch {
        Write-Host 'kubectl wait gagal, fallback polling manual...' -ForegroundColor Yellow
        $elapsed = 0
        $available = $false
        while ($elapsed -lt 180) {
            $replicas = kubectl get deployment ingress-nginx-controller -n ingress-nginx -o jsonpath='{.status.availableReplicas}' 2>$null
            if ($replicas -and [int]$replicas -gt 0) { $available = $true; break }
            Start-Sleep -Seconds 5
            $elapsed += 5
        }
        if (-not $available) { Write-Host 'WARNING: ingress-nginx-controller belum available.' -ForegroundColor Yellow }
    }

    Write-Host 'Memeriksa endpoints admission ingress-nginx...' -ForegroundColor Yellow
    $elapsed = 0
    $admissionReady = $false
    while ($elapsed -lt 180) {
        $ep = kubectl get endpoints ingress-nginx-controller-admission -n ingress-nginx --ignore-not-found -o jsonpath='{.subsets[*].addresses[*].ip}' 2>$null
        if ($ep) { $admissionReady = $true; break }
        Start-Sleep -Seconds 5
        $elapsed += 5
    }
    if ($admissionReady) { Write-Host 'Admission webhook ingress-nginx siap.' -ForegroundColor Green } else { Write-Host 'WARNING: admission webhook belum siap.' -ForegroundColor Yellow }
}

# 2. Pastikan namespace tersedia
$infraNamespaces = @(
    'suma-office','suma-office-general','suma-android','suma-pmo','suma-ecommerce','monitoring','suma-chat','elasticsearch','kibana','redis','suma-webhook'
)
foreach ($ns in $infraNamespaces) {
    try {
        kubectl create namespace $ns --dry-run=client -o yaml | kubectl apply -f - | Out-Null
    } catch {
        Write-Host ('Warning: gagal memastikan namespace {0}: {1}' -f $ns, $_.Exception.Message) -ForegroundColor Yellow
    }
}

# 3. Placeholder secret untuk suma-chat (dev convenience)
Write-Host 'Memastikan secret suma-chat-secret ada...' -ForegroundColor Cyan
try {
    $exists = kubectl get secret suma-chat-secret -n suma-chat --ignore-not-found -o name 2>$null
    if (-not $exists) {
        kubectl create secret generic suma-chat-secret -n suma-chat --from-literal=APP_KEY='dev-placeholder' --from-literal=DB_PASSWORD='dev-placeholder' --dry-run=client -o yaml | kubectl apply -f - | Out-Null
        Write-Host 'Secret suma-chat-secret dibuat (placeholder).' -ForegroundColor Green
    }
} catch {
    Write-Host ('Warning: gagal memastikan secret suma-chat-secret: {0}' -f $_.Exception.Message) -ForegroundColor Yellow
}

# 4. RBAC Monitoring
$monitoringRbac = Join-Path $PSScriptRoot 'monitoring\rbac.yaml'
if (Test-Path $monitoringRbac) {
    Write-Host 'Mengapply monitoring/rbac.yaml...' -ForegroundColor Cyan
    try { kubectl apply -f $monitoringRbac } catch { Write-Host ('Warning: gagal apply monitoring/rbac.yaml ({0})' -f $_.Exception.Message) -ForegroundColor Yellow }
}

# 5. PersistentVolumeClaims
$pvcFiles = @(
    'suma-ecommerce/pvc.yaml',
    'suma-office/pvc.yaml',
    'suma-office-general/pvc.yaml',
    'suma-android/pvc.yaml',
    'suma-pmo/pvc.yaml',
    'monitoring/pvc.yaml'
)
foreach ($relPath in $pvcFiles) {
    $fullPath = Join-Path $PSScriptRoot $relPath
    if (Test-Path $fullPath) {
        Write-Host ("Mengapply {0}..." -f $relPath) -ForegroundColor Cyan
        try { kubectl apply -f $fullPath } catch { Write-Host ('Warning: gagal apply {0} ({1})' -f $relPath, $_.Exception.Message) -ForegroundColor Yellow }
    }
}

# 6. Redis cluster (jika ada)
$redisManifest = Join-Path $PSScriptRoot 'redis\redis-cluster.yaml'
if (Test-Path $redisManifest) {
    Write-Host 'Mengapply redis/redis-cluster.yaml...' -ForegroundColor Cyan
    try {
        kubectl apply -f $redisManifest
        Write-Host 'Redis Cluster diapply (ingat: inisialisasi cluster manual setelah pod ready).' -ForegroundColor Green
    } catch {
        Write-Host ('Warning: gagal apply Redis cluster: {0}' -f $_.Exception.Message) -ForegroundColor Yellow
    }
}

# 7. SSL manual (folder ssl/)
$sslRoot = Join-Path $root 'ssl'
if (Test-Path $sslRoot) {
    Write-Host 'Memproses sertifikat manual dari folder ssl/...' -ForegroundColor Cyan
    $domainFolders = Get-ChildItem -Path $sslRoot -Directory | Select-Object -ExpandProperty Name

    $ingJson = $null
    try {
        $raw = kubectl get ingress --all-namespaces -o json 2>$null | Out-String
        if ($raw -and $raw.Trim()) { $ingJson = $raw | ConvertFrom-Json }
    } catch { $ingJson = $null }

    foreach ($domain in $domainFolders) {
        $domainPath = Join-Path $sslRoot $domain
        $crt = Join-Path $domainPath 'certificate.crt'
        $key = Join-Path $domainPath 'certificate.key'
        if (-not ((Test-Path $crt) -and (Test-Path $key))) {
            Write-Host ("Skipping {0}: certificate.crt atau certificate.key tidak ditemukan." -f $domain) -ForegroundColor Yellow
            continue
        }

        $safeName = ($domain.ToLower() -replace '\\.', '-' -replace '[^a-z0-9-]', '-').Trim('-')
        if (-not $safeName) { Write-Host ("Skipping folder domain tidak valid: {0}" -f $domain) -ForegroundColor Yellow; continue }

        $createdAny = $false
        if ($ingJson -and $ingJson.items -and $ingJson.items.Count -gt 0) {
            foreach ($it in $ingJson.items) {
                $ns = $it.metadata.namespace
                $tlsSecret = $null
                $hasHost = $false

                if ($it.spec -and $it.spec.tls) {
                    foreach ($t in $it.spec.tls) {
                        if ($t.hosts -and ($t.hosts -contains $domain)) {
                            $tlsSecret = $t.secretName
                            $hasHost = $true
                            break
                        }
                    }
                }

                if (-not $hasHost -and $it.spec -and $it.spec.rules) {
                    foreach ($r in $it.spec.rules) {
                        if ($r.host -and $r.host -eq $domain) {
                            $tlsSecret = 'tls-' + $safeName
                            $hasHost = $true
                            break
                        }
                    }
                }

                if ($hasHost -and $ns) {
                    Write-Host ("- Membuat secret TLS {0} di namespace {1} (domain {2})" -f $tlsSecret, $ns, $domain) -ForegroundColor Cyan
                    kubectl create namespace $ns --dry-run=client -o yaml | kubectl apply -f - | Out-Null
                    kubectl create secret tls $tlsSecret --cert=$crt --key=$key -n $ns --dry-run=client -o yaml | kubectl apply -f - | Out-Null
                    $createdAny = $true
                }
            }
        }

        if (-not $createdAny) {
            $namespace = $safeName
            $secretFallback = 'tls-' + $safeName
            Write-Host ("- Tidak ditemukan ingress yang cocok. Membuat namespace {0} dan secret {1}." -f $namespace, $secretFallback) -ForegroundColor Yellow
            kubectl create namespace $namespace --dry-run=client -o yaml | kubectl apply -f - | Out-Null
            kubectl create secret tls $secretFallback --cert=$crt --key=$key -n $namespace --dry-run=client -o yaml | kubectl apply -f - | Out-Null
        }
    }
} else {
    Write-Host 'Folder ssl/ tidak ditemukan, skip pembuatan secret manual.' -ForegroundColor Cyan
}

# 8. Copy cert-manager secrets jika diperlukan
$certManagerSecrets = @{
    'api-public-suma-honda-test-tls' = @('suma-ecommerce','suma-office','suma-office-general','suma-android','suma-pmo','suma-chat','suma-webhook','elasticsearch')
}

foreach ($secretName in $certManagerSecrets.Keys) {
    $sourceSecret = kubectl get secret $secretName -n cert-manager --ignore-not-found 2>$null
    if ($sourceSecret) {
        foreach ($targetNs in $certManagerSecrets[$secretName]) {
            $nsExists = kubectl get namespace $targetNs --ignore-not-found 2>$null
            if ($nsExists) {
                Write-Host ("Menyalin secret {0} ke namespace {1}" -f $secretName, $targetNs) -ForegroundColor Cyan
                try {
                    $secretData = kubectl get secret $secretName -n cert-manager -o json | ConvertFrom-Json
                    $secretData.metadata.namespace = $targetNs
                    $secretData.metadata.PSObject.Properties.Remove('resourceVersion')
                    $secretData.metadata.PSObject.Properties.Remove('uid')
                    $secretData.metadata.PSObject.Properties.Remove('creationTimestamp')
                    $secretData | ConvertTo-Json -Depth 10 | kubectl apply -f - | Out-Null
                } catch {
                    Write-Host ('Warning: gagal menyalin secret ke {0}: {1}' -f $targetNs, $_.Exception.Message) -ForegroundColor Yellow
                }
            }
        }
    } else {
        Write-Host ("Secret {0} tidak ditemukan di cert-manager." -f $secretName) -ForegroundColor Yellow
    }
}

# 9. ConfigMap dan monitoring stack
$officeConfig = Join-Path $PSScriptRoot 'suma-office\configmap.yaml'
if (Test-Path $officeConfig) { Write-Host 'Mengapply suma-office/configmap.yaml...' -ForegroundColor Cyan; kubectl apply -f $officeConfig }
$officeGenConfig = Join-Path $PSScriptRoot 'suma-office-general\configmap.yaml'
if (Test-Path $officeGenConfig) { Write-Host 'Mengapply suma-office-general/configmap.yaml...' -ForegroundColor Cyan; kubectl apply -f $officeGenConfig }
$monitoringConfig = Join-Path $PSScriptRoot 'monitoring\configmap.yaml'
if (Test-Path $monitoringConfig) { Write-Host 'Mengapply monitoring/configmap.yaml...' -ForegroundColor Cyan; kubectl apply -f $monitoringConfig }

$dashboardsDir = Join-Path $PSScriptRoot 'monitoring\dashboards'
if (Test-Path $dashboardsDir) {
    Write-Host 'Mengupdate ConfigMap Grafana dashboards...' -ForegroundColor Cyan
    kubectl delete configmap grafana-dashboards -n monitoring --ignore-not-found | Out-Null
    $files = Get-ChildItem -Path $dashboardsDir -Recurse -File -Include *.json
    if ($files) {
        $fromFileArgs = $files | ForEach-Object { '--from-file={0}' -f $_.FullName }
        $cmd = 'kubectl create configmap grafana-dashboards -n monitoring ' + ($fromFileArgs -join ' ')
        Invoke-Expression $cmd | Out-Null
    }
}

$monitoringDeploy = Join-Path $PSScriptRoot 'monitoring\deployment.yaml'
if (Test-Path $monitoringDeploy) { Write-Host 'Mengapply monitoring/deployment.yaml...' -ForegroundColor Cyan; kubectl apply -f $monitoringDeploy }

$monitoringSvc = Join-Path $PSScriptRoot 'monitoring\service.yaml'
if (Test-Path $monitoringSvc) { Write-Host 'Mengapply monitoring/service.yaml...' -ForegroundColor Cyan; kubectl apply -f $monitoringSvc }

# 9.5. Elasticsearch certificates & issuers
$esCertDir = Join-Path $PSScriptRoot 'elasticsearch'
if (Test-Path $esCertDir) {
    $certFiles = @('issuer-selfsigned.yaml','issuer-ca.yaml','ca-cert.yaml','node-cert.yaml')
    foreach ($certFile in $certFiles) {
        $certPath = Join-Path $esCertDir $certFile
        if (Test-Path $certPath) {
            Write-Host ("Mengapply elasticsearch/{0}..." -f $certFile) -ForegroundColor Cyan
            try { kubectl apply -f $certPath } catch { Write-Host ('Warning: gagal apply {0}: {1}' -f $certFile, $_.Exception.Message) -ForegroundColor Yellow }
        }
    }

    Write-Host 'Menunggu Certificate elasticsearch-ca Ready (timeout 120s)...' -ForegroundColor Yellow
    try {
        kubectl wait --for=condition=Ready certificate/elasticsearch-ca -n elasticsearch --timeout=120s | Out-Null
    } catch {
        Write-Host 'Certificate elasticsearch-ca belum Ready setelah 120s.' -ForegroundColor Yellow
    }

    $caSecret = kubectl get secret elasticsearch-ca -n elasticsearch --ignore-not-found -o name 2>$null
    if ($caSecret) {
        $existsInCm = kubectl get secret elasticsearch-ca -n cert-manager --ignore-not-found -o name 2>$null
        if (-not $existsInCm) {
            Write-Host 'Menyalin secret elasticsearch-ca ke namespace cert-manager...' -ForegroundColor Cyan
            try {
                kubectl get secret elasticsearch-ca -n elasticsearch -o yaml | ForEach-Object { $_ -replace 'namespace: elasticsearch','namespace: cert-manager' } | kubectl apply -f - | Out-Null
            } catch {
                Write-Host ('Warning: gagal menyalin elasticsearch-ca: {0}' -f $_.Exception.Message) -ForegroundColor Yellow
            }
        }
    } else {
        Write-Host 'Secret elasticsearch-ca belum terbentuk di namespace elasticsearch.' -ForegroundColor Yellow
    }

    Write-Host 'Menunggu Certificate elasticsearch-node-cert Ready (timeout 120s)...' -ForegroundColor Yellow
    try {
        kubectl wait --for=condition=Ready certificate/elasticsearch-node-cert -n elasticsearch --timeout=120s | Out-Null
    } catch {
        Write-Host 'Certificate elasticsearch-node-cert belum Ready setelah 120s.' -ForegroundColor Yellow
    }
}

# 10. Elasticsearch & Kibana sebagai bagian infra
$esFolder = Join-Path $PSScriptRoot 'elasticsearch'
if (Test-Path $esFolder) {
    Write-Host 'Deploying Elasticsearch...' -ForegroundColor Cyan
    $esStateful = Join-Path $esFolder 'statefulset.yaml'
    $esService = Join-Path $esFolder 'service.yaml'
    if (Test-Path $esStateful) { kubectl apply -f $esStateful }
    if (Test-Path $esService) { kubectl apply -f $esService }

    $esReady = $false
    Write-Host 'Menunggu Elasticsearch pods Ready (timeout 120s)...' -ForegroundColor Yellow
    try {
        kubectl wait --for=condition=Ready pods -l app=elasticsearch -n elasticsearch --timeout=120s 2>$null
        if ($LASTEXITCODE -eq 0) {
            $esReady = $true
            Write-Host 'Elasticsearch pods Ready.' -ForegroundColor Green
        }
    } catch {
        Write-Host 'kubectl wait tidak menemukan pods Elasticsearch, melakukan polling manual...' -ForegroundColor Yellow
    }

    if (-not $esReady) {
        $elapsed = 0
        while ($elapsed -lt 120) {
            $pods = kubectl get pods -n elasticsearch -l app=elasticsearch -o json 2>$null | ConvertFrom-Json
            if ($pods -and $pods.items) {
                $allReady = $true
                foreach ($pod in $pods.items) {
                    $readyCond = $pod.status.conditions | Where-Object { $_.type -eq 'Ready' }
                    if (-not ($readyCond -and $readyCond.status -eq 'True')) { $allReady = $false; break }
                }
                if ($allReady) { $esReady = $true; break }
            }
            Start-Sleep -Seconds 5
            $elapsed += 5
        }
        if ($esReady) { Write-Host 'Elasticsearch pods Ready.' -ForegroundColor Green } else { Write-Host 'Timeout menunggu Elasticsearch pods Ready.' -ForegroundColor Yellow }
    }

    $kibanaFolder = Join-Path $PSScriptRoot 'kibana'
    if (Test-Path $kibanaFolder) {
        if ($esReady) {
            Write-Host 'Menyiapkan secret Kibana encryption-key...' -ForegroundColor Cyan
            $kibanaSecretFile = Join-Path $kibanaFolder 'encryption-secret.yaml'
            $secretExists = kubectl get secret kibana-encryption-key -n kibana --ignore-not-found -o name 2>$null
            if (-not $secretExists) {
                if (Test-Path $kibanaSecretFile) {
                    try { kubectl apply -f $kibanaSecretFile -n kibana | Out-Null } catch { Write-Host 'Gagal apply encryption-secret.yaml, akan generate otomatis.' -ForegroundColor Yellow }
                }
                $secretExists = kubectl get secret kibana-encryption-key -n kibana --ignore-not-found -o name 2>$null
                if (-not $secretExists) {
                    $bytes = New-Object Byte[] 32
                    [System.Security.Cryptography.RNGCryptoServiceProvider]::Create().GetBytes($bytes)
                    $rand = [System.Convert]::ToBase64String($bytes)
                    kubectl create secret generic kibana-encryption-key -n kibana --from-literal=encryptionKey=$rand --dry-run=client -o yaml | kubectl apply -f - | Out-Null
                }
            }

            Write-Host 'Deploying Kibana...' -ForegroundColor Cyan
            $kibanaDeploy = Join-Path $kibanaFolder 'deployment.yaml'
            $kibanaService = Join-Path $kibanaFolder 'service.yaml'
            if (Test-Path $kibanaDeploy) { kubectl apply -f $kibanaDeploy -n kibana }
            if (Test-Path $kibanaService) { kubectl apply -f $kibanaService -n kibana }
        } else {
            Write-Host 'Skipping Kibana karena Elasticsearch belum Ready.' -ForegroundColor Yellow
        }
    }
} else {
    Write-Host 'Folder elasticsearch/ tidak ditemukan, melewati Elasticsearch & Kibana.' -ForegroundColor Yellow
}

# Konfirmasi sebelum lanjut deploy service
Write-Host ''
Write-Host '=== Infrastruktur selesai. Lanjut deploy service yang dipilih? ===' -ForegroundColor Green
$lanjut = Read-Host 'Ketik Y untuk lanjut, N untuk batal (Y/N)'
if ($lanjut -notmatch '^[Yy]$') {
    Write-Host 'Deployment service dibatalkan.' -ForegroundColor Yellow
    exit 0
}

# Deploy Service yang dipilih
if (-not $selectedIdx -or $selectedIdx.Count -eq 0) {
    Write-Host 'Tidak ada service dipilih. Hanya infrastruktur yang dijalankan.' -ForegroundColor Yellow
}

foreach ($idx in $selectedIdx) {
    if ($idx -ge 0 -and $idx -lt $services.Count) {
        $svc = $services[$idx]
        $repoDir = Join-Path $root $svc.RepoPath
        $k8sDir = Join-Path $PSScriptRoot $svc.K8sPath
        Write-Host ("=== Deploying {0} ===" -f $svc.Name) -ForegroundColor Cyan

        if (Test-Path $repoDir) {
            Push-Location $repoDir
            $dockerfilePath = $svc.Dockerfile
            if (-not (Test-Path $dockerfilePath)) {
                Write-Host ("Dockerfile {0} tidak ditemukan di {1}. Lewati build." -f $dockerfilePath, $repoDir) -ForegroundColor Yellow
            } else {
                docker build -t "$($svc.Image):$VERSION" -f $dockerfilePath .
                if ($LASTEXITCODE -ne 0) {
                    Write-Host "Error building $($svc.Image)." -ForegroundColor Red
                    Pop-Location
                    continue
                }
                docker tag "$($svc.Image):$VERSION" "$($svc.Image):latest"
            }
            Pop-Location
        } else {
            Write-Host ("Folder repository tidak ditemukan: {0}" -f $repoDir) -ForegroundColor Yellow
        }

        if (Test-Path $k8sDir) {
            $deployYaml = Join-Path $k8sDir 'deployment.yaml'
            $serviceYaml = Join-Path $k8sDir 'service.yaml'
            if (Test-Path $deployYaml) { kubectl apply -f $deployYaml } else { Write-Host ("deployment.yaml tidak ditemukan di {0}" -f $k8sDir) -ForegroundColor Yellow }
            if (Test-Path $serviceYaml) { kubectl apply -f $serviceYaml } else { Write-Host ("service.yaml tidak ditemukan di {0}" -f $k8sDir) -ForegroundColor Yellow }
        } else {
            Write-Host ("Folder manifest k8s tidak ditemukan: {0}" -f $k8sDir) -ForegroundColor Yellow
        }
    } else {
        Write-Host ("Pilihan service tidak valid: {0}" -f $idx) -ForegroundColor Yellow
    }
}

Write-Host '=== Deployment Selesai ===' -ForegroundColor Green

# Jalankan task scheduler dengan hak admin jika ada
$taskScript = Join-Path $PSScriptRoot 'update\suma-webhook-task-scheduler.ps1'
if (Test-Path $taskScript) {
    Write-Host 'Menjalankan suma-webhook-task-scheduler.ps1 dengan hak admin...' -ForegroundColor Cyan
    Start-Process powershell -ArgumentList "-File `"$taskScript`"" -Verb RunAs
}

# Jalankan createUserKibanaOnElasticsearch.ps1 jika ada
$userScript = Join-Path $PSScriptRoot 'update\createUserKibanaOnElasticsearch.ps1'
if (Test-Path $userScript) {
    Write-Host 'Menjalankan createUserKibanaOnElasticsearch.ps1 dengan hak admin...' -ForegroundColor Cyan
    Start-Process powershell -ArgumentList "-File `"$userScript`"" -Verb RunAs
}
