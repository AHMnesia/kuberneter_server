param(
    [string]$VERSION = 'v1.0.0'
)

function Test-ServiceDeployed {
    param(
        [Parameter(Mandatory=$true)]
        [hashtable]$Service
    )

    $deployment = $Service.Deployment
    $namespace = $Service.Namespace
    if (-not $deployment -or -not $namespace) { return $false }

    try {
        $result = kubectl get deployment $deployment -n $namespace --ignore-not-found -o name 2>$null
        if ($LASTEXITCODE -ne 0) { return $false }
        return -not [string]::IsNullOrWhiteSpace($result)
    } catch {
        return $false
    }
}

function Wait-ElasticsearchPodsReady {
    param(
        [int]$TimeoutSeconds = 300
    )

    $elapsed = 0
    while ($elapsed -lt $TimeoutSeconds) {
        try {
            $podsJson = kubectl get pods -n elasticsearch -l app=elasticsearch -o json 2>$null
            if ($LASTEXITCODE -eq 0 -and $podsJson) {
                $pods = $podsJson | ConvertFrom-Json
                if ($pods -and $pods.items -and $pods.items.Count -gt 0) {
                    $allReady = $true
                    foreach ($pod in $pods.items) {
                        $readyCond = $pod.status.conditions | Where-Object { $_.type -eq 'Ready' }
                        if (-not ($readyCond -and $readyCond.status -eq 'True')) { $allReady = $false; break }
                    }
                    if ($allReady) { return $true }
                }
            }
        } catch {
            # Abaikan error sementara (misalnya pod belum dibuat)
        }

        Start-Sleep -Seconds 5
        $elapsed += 5
    }

    return $false
}

# Menu: Pilih service yang ingin dideploy (atau pilih opsi Infrastruktur saja)
$services = @(
    @{ Name = 'Suma Ecommerce'; RepoPath = 'suma-ecommerce'; K8sPath = 'suma-ecommerce'; Image = 'suma-ecommerce-api'; Dockerfile = 'dockerfile'; Namespace = 'suma-ecommerce'; Deployment = 'suma-ecommerce-api' },
    @{ Name = 'Suma Office'; RepoPath = 'suma-office'; K8sPath = 'suma-office'; Image = 'suma-office-api'; Dockerfile = 'dockerfile.api'; Namespace = 'suma-office'; Deployment = 'suma-office-api' },
    @{ Name = 'Suma Office General'; RepoPath = 'suma-office'; K8sPath = 'suma-office-general'; Image = 'suma-office-general-api'; Dockerfile = 'dockerfile.api'; Namespace = 'suma-office-general'; Deployment = 'suma-office-general-api' },
    @{ Name = 'Suma Android'; RepoPath = 'suma-android'; K8sPath = 'suma-android'; Image = 'suma-android-api'; Dockerfile = 'dockerfile'; Namespace = 'suma-android'; Deployment = 'suma-android-api' },
    @{ Name = 'Suma PMO'; RepoPath = 'suma-pmo'; K8sPath = 'suma-pmo'; Image = 'suma-pmo-api'; Dockerfile = 'dockerfile'; Namespace = 'suma-pmo'; Deployment = 'suma-pmo-api' },
    @{ Name = 'Suma Chat'; RepoPath = 'suma-chat'; K8sPath = 'suma-chat'; Image = 'suma-chat'; Dockerfile = 'dockerfile'; Namespace = 'suma-chat'; Deployment = 'suma-chat' }
)
    $elasticReady = $false
    $elasticsearchApplied = $false
    $shouldDeployKibanaLater = $false
    $skipElasticWait = $false
    $deployInfraOnly = $false

Write-Host 'Mendeteksi service yang sudah terdeploy...' -ForegroundColor Cyan
$availableServices = @()
$skippedServices = @()
foreach ($svc in $services) {
    if (Test-ServiceDeployed -Service $svc) {
        $skippedServices += $svc
    } else {
        $availableServices += $svc
    }
}
if ($skippedServices.Count -gt 0) {
    Write-Host 'Service berikut sudah terdeteksi di cluster dan akan disembunyikan dari pilihan:' -ForegroundColor Yellow
    foreach ($svc in $skippedServices) {
        Write-Host (" - {0} (namespace: {1})" -f $svc.Name, $svc.Namespace) -ForegroundColor DarkYellow
    }
}

$selectedServices = @()
$selectedIdx = @()
$selectedNames = [System.Collections.Generic.HashSet[string]]::new()
# HashSet untuk menandai folder k8s service yang dipilih (dipakai saat apply resource infra opsional)
$selectedK8sPaths = [System.Collections.Generic.HashSet[string]]::new()
if ($availableServices.Count -gt 0) {
    Write-Host '=== Pilih Service yang akan dideploy ===' -ForegroundColor Cyan
    for ($i=0; $i -lt $availableServices.Count; $i++) {
        Write-Host ("[$i] {0}" -f $availableServices[$i].Name) -ForegroundColor Yellow
    }
    Write-Host '[I] Deploy Infrastruktur saja (tanpa service apapun)' -ForegroundColor Yellow
    $selected = Read-Host 'Masukkan nomor service yang ingin dideploy (pisahkan dengan koma, contoh: 0,2,3) atau ketik I untuk Infrastruktur saja'
    if ($selected.Trim().ToUpperInvariant() -eq 'I') {
        $deployInfraOnly = $true
        $selectedIdx = @()
    } else {
        $selectedIdx = $selected -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ -match '^\d+$' }
    }
    foreach ($idx in $selectedIdx) {
        if ($idx -ge 0 -and $idx -lt $availableServices.Count) {
            $svcObj = $availableServices[$idx]
            if ($selectedNames.Add($svcObj.Name)) {
                $selectedServices += $svcObj
                $null = $selectedK8sPaths.Add($svcObj.K8sPath.ToLower())
            } else {
                Write-Host ("Duplikasi pilihan diabaikan: {0}" -f $svcObj.Name) -ForegroundColor Yellow
            }
        } else {
            Write-Host ("Pilihan service tidak valid: {0}" -f $idx) -ForegroundColor Yellow
        }
    }
} else {
    Write-Host 'Semua service sudah terdeploy. Lewati tahap pemilihan service.' -ForegroundColor Yellow
}

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

# 5. PersistentVolumeClaims (hanya resource infra default)
$pvcFiles = @(
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

$monitoringIngress = Join-Path $PSScriptRoot 'monitoring\ingress.yaml'
if (Test-Path $monitoringIngress) { Write-Host 'Mengapply monitoring/ingress.yaml...' -ForegroundColor Cyan; kubectl apply -f $monitoringIngress }

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

    # Pastikan secret elasticsearch-ssl tersedia sebelum StatefulSet dijalankan
    $esTlsSecretReady = $false
    $elapsed = 0
    while ($elapsed -lt 120) {
        $secret = kubectl get secret elasticsearch-ssl -n elasticsearch --ignore-not-found -o name 2>$null
        if ($secret) { $esTlsSecretReady = $true; break }
        Start-Sleep -Seconds 5
        $elapsed += 5
    }
    if ($esTlsSecretReady) {
        Write-Host 'Secret elasticsearch-ssl tersedia.' -ForegroundColor Green
    } else {
        Write-Host 'WARNING: Secret elasticsearch-ssl belum ditemukan. StatefulSet mungkin gagal saat mount SSL.' -ForegroundColor Yellow
    }
}

# 10. Elasticsearch sebagai bagian infra (Kibana akan dieksekusi di tahap akhir)
$esFolder = Join-Path $PSScriptRoot 'elasticsearch'
$kibanaFolderPath = Join-Path $PSScriptRoot 'kibana'
if (Test-Path $esFolder) {
    $elasticsearchApplied = $true
    if (Test-Path $kibanaFolderPath) { $shouldDeployKibanaLater = $true }

    Write-Host 'Deploying Elasticsearch...' -ForegroundColor Cyan
    $esStateful = Join-Path $esFolder 'statefulset.yaml'
    $esService = Join-Path $esFolder 'service.yaml'
    $esNetworkPolicy = Join-Path $esFolder 'networkpolicy.yaml'
    $esPdb = Join-Path $esFolder 'poddisruptionbudget.yaml'
    $esIngress = Join-Path $esFolder 'ingress.yaml'
    if (Test-Path $esStateful) { kubectl apply -f $esStateful }
    if (Test-Path $esService) { kubectl apply -f $esService }
    if (Test-Path $esPdb) { kubectl apply -f $esPdb }
    if (Test-Path $esNetworkPolicy) { kubectl apply -f $esNetworkPolicy }
    if (Test-Path $esIngress) { kubectl apply -f $esIngress }

    # Defer waiting for the Elasticsearch rollout here — we'll verify readiness later (before deploying Kibana/creating users)
    Write-Host 'Melewatkan penantian immediate rollout untuk Elasticsearch. Verifikasi readiness akan dilakukan sebelum deploy Kibana.' -ForegroundColor Yellow
    $rolloutSucceeded = $false
    $elasticReady = $false
} else {
    Write-Host 'Folder elasticsearch/ tidak ditemukan, melewati deployment Elasticsearch.' -ForegroundColor Yellow
    if (Test-Path $kibanaFolderPath) {
        $shouldDeployKibanaLater = $true
        Write-Host 'Catatan: Kibana ditemukan namun akan dilewati karena Elasticsearch tidak tersedia.' -ForegroundColor Yellow
    }
}

# Konfirmasi sebelum lanjut deploy service
Write-Host ''
Write-Host '=== Infrastruktur selesai. Lanjut deploy service yang dipilih? ===' -ForegroundColor Green
if ($deployInfraOnly) {
    Write-Host 'Opsi "Deploy Infrastruktur saja" dipilih. Melanjutkan ke langkah akhir (Kibana dan post-infra).' -ForegroundColor Green
    # Do not exit; we skip service deployment but still run Kibana and post-infra scripts
    $lanjut = 'Y'
} else {
    $lanjut = Read-Host 'Ketik Y untuk lanjut, N untuk batal (Y/N)'
    if ($lanjut -notmatch '^[Yy]$') {
        Write-Host 'Deployment service dibatalkan.' -ForegroundColor Yellow
        exit 0
    }
}

# Deploy Service yang dipilih
if (-not $selectedServices -or $selectedServices.Count -eq 0) {
    Write-Host 'Tidak ada service dipilih. Hanya infrastruktur yang dijalankan.' -ForegroundColor Yellow
}

foreach ($svc in $selectedServices) {
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
        if ($svc.Namespace) {
            try {
                kubectl create namespace $svc.Namespace --dry-run=client -o yaml | kubectl apply -f - | Out-Null
            } catch {
                Write-Host ("Warning: gagal memastikan namespace {0}: {1}" -f $svc.Namespace, $_.Exception.Message) -ForegroundColor Yellow
            }
        }

        $namespaceManifest = Get-ChildItem -Path $k8sDir -Filter 'namespace.yaml' -Recurse -File | Select-Object -First 1
        if ($namespaceManifest) {
            Write-Host ("Mengapply {0}/{1} terlebih dahulu..." -f $svc.Name, $namespaceManifest.Name) -ForegroundColor DarkCyan
            kubectl apply -f $namespaceManifest.FullName
        }

        $yamlFiles = Get-ChildItem -Path $k8sDir -Recurse -Filter '*.yaml' -File | Sort-Object FullName
        if (-not $yamlFiles) {
            Write-Host ("Tidak menemukan file YAML di {0}" -f $k8sDir) -ForegroundColor Yellow
        }

        foreach ($file in $yamlFiles) {
            if ($namespaceManifest -and ($file.FullName -eq $namespaceManifest.FullName)) { continue }
            Write-Host ("Mengapply {0}/{1}..." -f $svc.Name, $file.FullName.Substring($k8sDir.Length + 1)) -ForegroundColor DarkCyan
            kubectl apply -f $file.FullName
        }
    } else {
        Write-Host ("Folder manifest k8s tidak ditemukan: {0}" -f $k8sDir) -ForegroundColor Yellow
    }
}

# Deploy Kibana di akhir setelah memastikan Elasticsearch
if ($shouldDeployKibanaLater) {
    Write-Host ''
    Write-Host '=== Tahap Akhir: Deploy Kibana ===' -ForegroundColor Green

    if (-not $elasticsearchApplied) {
        Write-Host 'Elasticsearch tidak di-deploy pada tahap infra, skip Kibana.' -ForegroundColor Yellow
    } else {
        if (-not $elasticReady) {
            if ($skipElasticWait) {
                Write-Host 'Elasticsearch ditandai skip. Kibana tidak akan dideploy pada eksekusi ini.' -ForegroundColor Yellow
            } else {
                Write-Host 'Elasticsearch belum Ready. Menunggu tambahan 180s sebelum mencoba deploy Kibana...' -ForegroundColor Yellow
                try {
                    kubectl rollout status statefulset/elasticsearch -n elasticsearch --timeout=180s | Out-Null
                    if ($LASTEXITCODE -eq 0) { $elasticReady = $true }
                } catch {
                    Write-Host 'Rollout Elasticsearch masih belum siap setelah penantian tambahan.' -ForegroundColor Yellow
                }

                if (-not $elasticReady) {
                    $elapsed = 0
                    while ($elapsed -lt 180 -and -not $elasticReady) {
                        try {
                            $podsJson = kubectl get pods -n elasticsearch -l app=elasticsearch -o json 2>$null
                            if ($LASTEXITCODE -eq 0 -and $podsJson) {
                                $pods = $podsJson | ConvertFrom-Json
                                if ($pods -and $pods.items -and $pods.items.Count -gt 0) {
                                    $allReady = $true
                                    foreach ($pod in $pods.items) {
                                        $readyCond = $pod.status.conditions | Where-Object { $_.type -eq 'Ready' }
                                        if (-not ($readyCond -and $readyCond.status -eq 'True')) { $allReady = $false; break }
                                    }
                                    if ($allReady) { $elasticReady = $true; break }
                                }
                            }
                        } catch {
                            # abaikan error polling
                        }
                        Start-Sleep -Seconds 5
                        $elapsed += 5
                    }
                }
            }
        }

        if ($elasticReady) {
            Write-Host 'Menyiapkan secret Kibana encryption-key...' -ForegroundColor Cyan
            $kibanaSecretFile = Join-Path $kibanaFolderPath 'encryption-secret.yaml'
            $secretExists = kubectl get secret kibana-encryption-key -n kibana --ignore-not-found -o name 2>$null
            if (-not $secretExists) {
                if (Test-Path $kibanaSecretFile) {
                    try { kubectl apply -f $kibanaSecretFile -n kibana | Out-Null } catch { Write-Host 'Gagal apply encryption-secret.yaml, generate otomatis.' -ForegroundColor Yellow }
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
            # Pastikan namespace kibana ada
            try {
                kubectl create namespace kibana --dry-run=client -o yaml | kubectl apply -f - | Out-Null
            } catch {
                Write-Host ("Warning: gagal memastikan namespace kibana: {0}" -f $_.Exception.Message) -ForegroundColor Yellow
            }

            # Jika ada namespace.yaml dalam folder kibana, apply terlebih dahulu
            $kibanaNamespaceManifest = Get-ChildItem -Path $kibanaFolderPath -Filter 'namespace.yaml' -Recurse -File | Select-Object -First 1
            if ($kibanaNamespaceManifest) {
                Write-Host ("Mengapply {0}..." -f $kibanaNamespaceManifest.FullName) -ForegroundColor DarkCyan
                try { kubectl apply -f $kibanaNamespaceManifest.FullName | Out-Null } catch { Write-Host ("Warning: gagal apply {0}: {1}" -f $kibanaNamespaceManifest.FullName, $_.Exception.Message) -ForegroundColor Yellow }
            }

            # Apply semua YAML di folder kibana (rekursif). Coba apply dengan -n kibana terlebih dahulu, fallback ke tanpa -n jika gagal.
            $kibanaYamlFiles = Get-ChildItem -Path $kibanaFolderPath -Recurse -Filter '*.yaml' -File | Sort-Object FullName
            if (-not $kibanaYamlFiles) {
                Write-Host 'deployment/service dan file YAML untuk Kibana tidak ditemukan.' -ForegroundColor Yellow
            } else {
                foreach ($file in $kibanaYamlFiles) {
                    if ($kibanaNamespaceManifest -and ($file.FullName -eq $kibanaNamespaceManifest.FullName)) { continue }
                    Write-Host ("Mengapply kibana/{0}..." -f $file.FullName.Substring($kibanaFolderPath.Length + 1)) -ForegroundColor DarkCyan
                    try {
                        kubectl apply -f $file.FullName -n kibana | Out-Null
                    } catch {
                        # Fallback: apply tanpa override namespace (file mungkin sudah memiliki namespace)
                        try {
                            kubectl apply -f $file.FullName | Out-Null
                        } catch {
                            Write-Host ("Warning: gagal apply {0}: {1}" -f $file.FullName, $_.Exception.Message) -ForegroundColor Yellow
                        }
                    }
                }
            }
        } else {
            if ($skipElasticWait) {
                Write-Host 'Kibana dilewati karena Elasticsearch ditandai skip pada sesi ini.' -ForegroundColor Yellow
            } else {
                Write-Host 'Elasticsearch tetap belum Ready. Kibana tidak akan dideploy pada eksekusi ini.' -ForegroundColor Yellow
            }
        }
    }
}

# Jalankan task scheduler dengan hak admin jika ada
$taskScript = Join-Path $PSScriptRoot 'update\suma-webhook-task-scheduler.ps1'
function Invoke-ProcessElevated {
    param(
        [Parameter(Mandatory=$true)][string]$ScriptPath,
        [int]$MaxRetries = 3
    )

    $attempt = 0
    while ($attempt -lt $MaxRetries) {
        $attempt++
        Write-Host ("Mencoba menjalankan (elevated) {0} (percobaan {1}/{2})..." -f $ScriptPath, $attempt, $MaxRetries) -ForegroundColor Cyan
        try {
            Start-Process powershell -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$ScriptPath`"" -Verb RunAs -Wait -WindowStyle Hidden
            # If Start-Process -Wait returns without exception, assume success
            Write-Host 'Process elevated selesai.' -ForegroundColor Green
            return $true
        } catch {
            Write-Host 'Permintaan elevasi dibatalkan atau gagal.' -ForegroundColor Yellow
            if ($attempt -lt $MaxRetries) {
                $resp = Read-Host 'UAC dibatalkan atau gagal. Coba ulang meminta hak Administrator? (Y/N)'
                if ($resp.ToUpperInvariant() -ne 'Y') { break }
                continue
            }
        }
    }

    return $false
}

if (Test-Path $taskScript) {
    # First try to run elevated, with a couple of retries if the user cancels UAC
    $ok = Invoke-ProcessElevated -ScriptPath $taskScript -MaxRetries 3
    if (-not $ok) {
        Write-Host 'Tidak dapat menjalankan dengan elevasi atau user menolak UAC. Menjalankan tanpa elevasi sebagai fallback...' -ForegroundColor Yellow
        try {
            & powershell -NoProfile -ExecutionPolicy Bypass -File $taskScript
        } catch {
            Write-Host ("Task scheduler gagal dijalankan, script ini harus dijalankan dengan hak Administrator. Error: {0}" -f $_.Exception.Message) -ForegroundColor Red
        }
    }
}

# Jalankan createUserKibanaOnElasticsearch.ps1 jika ada
$userScript = Join-Path $PSScriptRoot 'update\createUserKibanaOnElasticsearch.ps1'
if (Test-Path $userScript) {
    Write-Host 'Menjalankan createUserKibanaOnElasticsearch.ps1...' -ForegroundColor Cyan
    try {
        # Run in-process so it inherits the current user's environment (kubeconfig, PATH, etc.)
        & $userScript
    } catch {
        Write-Host ("Gagal menjalankan {0}: {1}" -f $userScript, $_.Exception.Message) -ForegroundColor Red
        Write-Host 'Jika Anda memerlukan elevasi (UAC), jalankan script ini manual sebagai Administrator.' -ForegroundColor Yellow
    }
} else {
    Write-Host 'Script createUserKibanaOnElasticsearch.ps1 tidak ditemukan.' -ForegroundColor Yellow
}

Write-Host ''
Write-Host '=== Deployment Selesai ===' -ForegroundColor Green
