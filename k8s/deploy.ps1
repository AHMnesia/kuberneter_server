param(
    [string]$VERSION = 'v1.0.0'
)

# Early parse-check: compile the script to detect syntax errors early when running directly
try {
    $scriptPath = $MyInvocation.MyCommand.Path
    if ($scriptPath) {
        $scriptText = Get-Content -Path $scriptPath -Raw
        [ScriptBlock]::Create($scriptText) | Out-Null
    }
} catch {
    Write-Host 'ERROR: Terjadi kesalahan sintaks pada deploy.ps1. Hentikan.' -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    exit 1
}

# Build images (services only) - optional
$root = Split-Path $PSScriptRoot -Parent   # c:\docker
$ecomDir = Join-Path $root 'suma-ecommerce'
$officeDir = Join-Path $root 'suma-office'
$androidDir = Join-Path $root 'suma-android'
$pmoDir = Join-Path $root 'suma-pmo'
$chatDir = Join-Path $root 'suma-chat'

Write-Host '=== Building Docker Images ===' -ForegroundColor Green

if (Test-Path $ecomDir) {
    Write-Host '1. Building Suma Ecommerce API...' -ForegroundColor Yellow
    Push-Location $ecomDir
    docker build -t "suma-ecommerce-api:${VERSION}" -f dockerfile .
    if ($LASTEXITCODE -ne 0) { Write-Host 'Error building suma-ecommerce-api' -ForegroundColor Red; Pop-Location; exit 1 }
    docker tag "suma-ecommerce-api:${VERSION}" 'suma-ecommerce-api:latest'
    Pop-Location
} else {
    Write-Host ('Warning: Folder tidak ditemukan: {0}' -f $ecomDir) -ForegroundColor Yellow
}

if (Test-Path $officeDir) {
    Write-Host '2. Building Suma Office API (shared for both office & office-general)...' -ForegroundColor Yellow
    Push-Location $officeDir
    
    # Build one image that will be used for both suma-office and suma-office-general
    docker build -t "suma-office-api:${VERSION}" -f dockerfile.api .
    if ($LASTEXITCODE -ne 0) { Write-Host 'Error building suma-office-api' -ForegroundColor Red; Pop-Location; exit 1 }
    
    # Tag the same image for both services
    docker tag "suma-office-api:${VERSION}" 'suma-office-api:latest'
    docker tag "suma-office-api:${VERSION}" "suma-office-general-api:${VERSION}"
    docker tag "suma-office-api:${VERSION}" 'suma-office-general-api:latest'
    
    Pop-Location
} else {
    Write-Host ('Warning: Folder tidak ditemukan: {0}' -f $officeDir) -ForegroundColor Yellow
}

if (Test-Path $androidDir) {
    Write-Host '4. Building Suma Android API...' -ForegroundColor Yellow
    Push-Location $androidDir
    docker build -t "suma-android-api:${VERSION}" -f dockerfile .
    if ($LASTEXITCODE -ne 0) { Write-Host 'Error building suma-android-api' -ForegroundColor Red; Pop-Location; exit 1 }
    docker tag "suma-android-api:${VERSION}" 'suma-android-api:latest'
    Pop-Location
} else {
    Write-Host ('Warning: Folder tidak ditemukan: {0}' -f $androidDir) -ForegroundColor Yellow
}

if (Test-Path $pmoDir) {
    Write-Host '4. Building Suma PMO API...' -ForegroundColor Yellow
    Push-Location $pmoDir
    docker build -t "suma-pmo-api:${VERSION}" -f dockerfile .
    if ($LASTEXITCODE -ne 0) { Write-Host 'Error building suma-pmo-api' -ForegroundColor Red; Pop-Location; exit 1 }
    docker tag "suma-pmo-api:${VERSION}" 'suma-pmo-api:latest'
    Pop-Location
} else {
    Write-Host ('Warning: Folder tidak ditemukan: {0}' -f $pmoDir) -ForegroundColor Yellow
}

if (Test-Path $chatDir) {
    Write-Host '4. Building Suma Chat...' -ForegroundColor Yellow
    Push-Location $chatDir
    docker build -t "suma-chat:${VERSION}" -f dockerfile .
    if ($LASTEXITCODE -ne 0) { Write-Host 'Error building suma-chat' -ForegroundColor Red; Pop-Location; exit 1 }
    docker tag "suma-chat:${VERSION}" 'suma-chat:latest'
    Pop-Location
} else {
    Write-Host ('Warning: Folder tidak ditemukan: {0}' -f $chatDir) -ForegroundColor Yellow
}

Write-Host '=== Build Complete ===' -ForegroundColor Green
Write-Host ('Built images:') -ForegroundColor Cyan
Write-Host ('  - suma-ecommerce-api:{0}' -f $VERSION) -ForegroundColor White
Write-Host ('  - suma-office-api:{0}' -f $VERSION) -ForegroundColor White
Write-Host ('  - suma-office-general-api:{0}' -f $VERSION) -ForegroundColor White
Write-Host ('  - suma-android-api:{0}' -f $VERSION) -ForegroundColor White
Write-Host ('  - suma-pmo-api:{0}' -f $VERSION) -ForegroundColor White
Write-Host ('  - suma-chat:{0}' -f $VERSION) -ForegroundColor White

# Ensure working dir
Set-Location $PSScriptRoot

Write-Host 'Starting Kubernetes Deployment...' -ForegroundColor Green

# If vendor manifests exist in k8s/vendors, ensure vendor components are present and wait for ingress controller to be ready.
if (Test-Path (Join-Path $PSScriptRoot 'vendors')) {
    Write-Host 'Detected vendors/ folder. Ensuring vendor manifests (cert-manager, ingress-nginx, metrics-server) are applied...' -ForegroundColor Cyan

    $helmValues = Join-Path $PSScriptRoot 'vendors\helm-values.yaml'
    $helmCmd = Get-Command helm -ErrorAction SilentlyContinue

    if ($helmCmd) {
        if (Test-Path $helmValues) {
            Write-Host 'Helm detected and helm-values.yaml present — deploying ingress-nginx with Helm using provided values...' -ForegroundColor Cyan
            try {
                helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx | Out-Null
                helm repo update | Out-Null
                kubectl create namespace ingress-nginx --dry-run=client -o yaml | kubectl apply -f - | Out-Null
                helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx --namespace ingress-nginx -f "$helmValues"
                Write-Host 'Helm deployment command issued for ingress-nginx.' -ForegroundColor Green
            } catch {
                Write-Host ('Warning: Helm deploy failed: {0}' -f $_.Exception.Message) -ForegroundColor Yellow
                Write-Host 'Falling back to applying YAMLs from vendors/ directory...' -ForegroundColor Yellow
                try { kubectl apply -f (Join-Path $PSScriptRoot 'vendors') --recursive } catch { Write-Host 'Warning: kubectl apply vendors failed.' -ForegroundColor Yellow }
            }
        } else {
            Write-Host 'Helm detected but helm-values.yaml not found — attempting Helm install with chart defaults...' -ForegroundColor Cyan
            try {
                helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx | Out-Null
                helm repo update | Out-Null
                kubectl create namespace ingress-nginx --dry-run=client -o yaml | kubectl apply -f - | Out-Null
                helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx --namespace ingress-nginx
                Write-Host 'Helm deployment command issued for ingress-nginx (chart defaults).' -ForegroundColor Green
            } catch {
                Write-Host ('Warning: Helm deploy failed: {0}' -f $_.Exception.Message) -ForegroundColor Yellow
                Write-Host 'Falling back to applying YAMLs from vendors/ directory...' -ForegroundColor Yellow
                try { kubectl apply -f (Join-Path $PSScriptRoot 'vendors') --recursive } catch { Write-Host 'Warning: kubectl apply vendors failed.' -ForegroundColor Yellow }
            }
        }
    } else {
        Write-Host 'Helm not found; applying any YAML files in vendors/ with kubectl...' -ForegroundColor Cyan
        try { kubectl apply -f (Join-Path $PSScriptRoot 'vendors') --recursive } catch { Write-Host 'Warning: kubectl apply vendors failed.' -ForegroundColor Yellow }
    }

    # Ensure cert-manager CRDs and metrics-server are present before applying Certificates/ClusterIssuers later
    $certManagerFile = Join-Path $PSScriptRoot 'vendors\cert-manager.yaml'
    $metricsServerFile = Join-Path $PSScriptRoot 'vendors\metrics-server.yaml'
    if (Test-Path $certManagerFile) {
        Write-Host 'Applying cert-manager (CRDs + components) from vendors/cert-manager.yaml...' -ForegroundColor Cyan
        try { kubectl apply -f $certManagerFile } catch { Write-Host 'Warning: failed to apply cert-manager.yaml' -ForegroundColor Yellow }
    }
    if (Test-Path $metricsServerFile) {
        Write-Host 'Applying metrics-server from vendors/metrics-server.yaml...' -ForegroundColor Cyan
        try { kubectl apply -f $metricsServerFile } catch { Write-Host 'Warning: failed to apply metrics-server.yaml' -ForegroundColor Yellow }
    }

    # Wait for cert-manager webhook to be ready before applying ClusterIssuer/Certificate manifests
    if (Test-Path $certManagerFile) {
        Write-Host 'Waiting for cert-manager webhook to become ready (timeout 120s)...' -ForegroundColor Yellow
        $cmTimeout = 120
        $cmReady = $false
        $elapsed = 0
        while ($elapsed -lt $cmTimeout) {
            try {
                # Check if cert-manager pods are ready
                $cmPods = kubectl get pods -n cert-manager --field-selector=status.phase=Running -o jsonpath='{.items[*].metadata.name}' 2>$null
                if ($cmPods) {
                    # Check if webhook service has endpoints
                    $webhookEp = kubectl get endpoints cert-manager-webhook -n cert-manager --ignore-not-found -o jsonpath='{.subsets[*].addresses[*].ip}' 2>$null
                    if ($webhookEp) {
                        Write-Host 'cert-manager webhook is ready.' -ForegroundColor Green
                        $cmReady = $true
                        break
                    }
                }
            } catch {
                # ignore check errors
            }
            Start-Sleep -Seconds 5
            $elapsed += 5
        }
        if (-not $cmReady) {
            Write-Host 'WARNING: cert-manager webhook did not become ready within timeout. ClusterIssuer apply may fail.' -ForegroundColor Yellow
        }
    }

    $certsDir = Join-Path $PSScriptRoot 'certs'
    if (Test-Path $certsDir) {
        Write-Host 'Applying ClusterIssuer/Certificate manifests from certs/...' -ForegroundColor Cyan
        try {
            kubectl apply -f $certsDir --recursive
            Write-Host 'Applied certs/ manifests.' -ForegroundColor Green
        } catch {
            Write-Host ('Warning: failed to apply certs/: {0}' -f $_.Exception.Message) -ForegroundColor Yellow
        }
    }

    # Install Prometheus Operator CRDs (required for ServiceMonitor resources)
    Write-Host 'Installing Prometheus Operator CRDs (required for monitoring ServiceMonitors)...' -ForegroundColor Cyan
    try {
        kubectl apply -f https://raw.githubusercontent.com/prometheus-operator/prometheus-operator/main/example/prometheus-operator-crd/monitoring.coreos.com_servicemonitors.yaml
        kubectl apply -f https://raw.githubusercontent.com/prometheus-operator/prometheus-operator/main/example/prometheus-operator-crd/monitoring.coreos.com_prometheusrules.yaml
        kubectl apply -f https://raw.githubusercontent.com/prometheus-operator/prometheus-operator/main/example/prometheus-operator-crd/monitoring.coreos.com_podmonitors.yaml
        kubectl apply -f https://raw.githubusercontent.com/prometheus-operator/prometheus-operator/main/example/prometheus-operator-crd/monitoring.coreos.com_prometheuses.yaml
        kubectl apply -f https://raw.githubusercontent.com/prometheus-operator/prometheus-operator/main/example/prometheus-operator-crd/monitoring.coreos.com_alertmanagers.yaml
        Write-Host 'Prometheus Operator CRDs installed successfully.' -ForegroundColor Green
    } catch {
        Write-Host ('Warning: Failed to install Prometheus Operator CRDs: {0}' -f $_.Exception.Message) -ForegroundColor Yellow
        Write-Host 'Monitoring ServiceMonitors may not work without these CRDs.' -ForegroundColor Yellow
    }

    # Wait for ingress-nginx controller to be available before deploying apps that depend on the ingress
    Write-Host 'Waiting for ingress-nginx controller to become Available (timeout 180s)...' -ForegroundColor Yellow
    $waitTimeout = 180
    $waitSucceeded = $false
    try {
        kubectl wait --for=condition=Available deployment/ingress-nginx-controller -n ingress-nginx --timeout="${waitTimeout}s"
        if ($LASTEXITCODE -eq 0) { $waitSucceeded = $true }
    } catch {
        Write-Host 'kubectl wait failed or timed out; falling back to polling pods...' -ForegroundColor Yellow
    }

    if (-not $waitSucceeded) {
        $elapsed = 0
        while ($elapsed -lt $waitTimeout) {
            $available = kubectl get deployment ingress-nginx-controller -n ingress-nginx -o jsonpath='{.status.availableReplicas}' 2>$null
            if ($available -and [int]$available -gt 0) {
                Write-Host 'Ingress controller is available.' -ForegroundColor Green
                $waitSucceeded = $true
                break
            }
            Start-Sleep -Seconds 5
            $elapsed += 5
        }
    }

    if (-not $waitSucceeded) {
        Write-Host 'WARNING: ingress-nginx controller did not become ready within timeout. Continuing deployment, but ingress may not work yet.' -ForegroundColor Yellow
    }

    # Wait for admission webhook service endpoints so server-side validation won't fail
    Write-Host 'Checking ingress admission webhook endpoints (ingress-nginx-controller-admission)...' -ForegroundColor Yellow
    $admissionTimeout = $waitTimeout
    $admissionOk = $false
    $admissionSvc = 'ingress-nginx-controller-admission'
    $elapsed = 0
    while ($elapsed -lt $admissionTimeout) {
        $ep = kubectl get endpoints $admissionSvc -n ingress-nginx --ignore-not-found -o jsonpath='{.subsets[*].addresses[*].ip}' 2>$null
        if ($ep) { $admissionOk = $true; break }
        Start-Sleep -Seconds 5
        $elapsed += 5
    }
    if ($admissionOk) { Write-Host 'Admission webhook endpoints are ready.' -ForegroundColor Green } else { Write-Host 'WARNING: admission webhook endpoints not ready; Ingress creation may fail with webhook connection refused.' -ForegroundColor Yellow }
}

Write-Host '4. Creating namespaces...' -ForegroundColor Yellow
# create namespaces used by the manifests
kubectl create namespace suma-office --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace suma-office-general --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace suma-android --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace suma-pmo --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace suma-ecommerce --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace suma-chat --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace elasticsearch --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace kibana --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace redis --dry-run=client -o yaml | kubectl apply -f -

# Create placeholder suma-chat-secret if missing (helps local dev deploy)
Write-Host 'Checking suma-chat secret...' -ForegroundColor Cyan
$exists = kubectl get secret suma-chat-secret -n suma-chat --ignore-not-found -o name 2>$null
if (-not $exists) {
    Write-Host 'suma-chat-secret not found - creating placeholder secret (use real values in production).' -ForegroundColor Yellow
    kubectl create secret generic suma-chat-secret -n suma-chat --from-literal=APP_KEY='dev-placeholder' --from-literal=DB_PASSWORD='dev-placeholder' --dry-run=client -o yaml | kubectl apply -f -
}

Write-Host '5. Creating RBAC for monitoring (if present)...' -ForegroundColor Yellow
if (Test-Path 'monitoring/rbac.yaml') { kubectl apply -f monitoring/rbac.yaml }

Write-Host '6. Creating persistent volumes (if present)...' -ForegroundColor Yellow
if (Test-Path 'suma-ecommerce/pvc.yaml') { kubectl apply -f suma-ecommerce/pvc.yaml }
if (Test-Path 'suma-office/pvc.yaml') { kubectl apply -f suma-office/pvc.yaml }
if (Test-Path 'suma-office-general/pvc.yaml') { kubectl apply -f suma-office-general/pvc.yaml }
if (Test-Path 'suma-android/pvc.yaml') { kubectl apply -f suma-android/pvc.yaml }
if (Test-Path 'suma-pmo/pvc.yaml') { kubectl apply -f suma-pmo/pvc.yaml }
if (Test-Path 'monitoring/pvc.yaml') { kubectl apply -f monitoring/pvc.yaml }

Write-Host '6.5. Deploying Redis Cluster...' -ForegroundColor Yellow
if (Test-Path 'redis/redis-cluster.yaml') { 
    kubectl apply -f redis/redis-cluster.yaml 
    Write-Host 'Redis Cluster deployed. Note: Manual cluster initialization required after pods are ready.' -ForegroundColor Cyan
}

# SSL/manual TLS section
Write-Host '7. Creating SSL secrets from ssl/ folder (if present)...' -ForegroundColor Yellow
$sslRoot = Join-Path $root 'ssl'

if (Test-Path $sslRoot) {
    $domainFolders = Get-ChildItem -Path $sslRoot -Directory | Select-Object -ExpandProperty Name

    # load all ingresses once (if any) so we can match hosts -> expected secretName + namespace
    $ingJson = $null
    try {
        $raw = kubectl get ingress --all-namespaces -o json 2>$null | Out-String
        if ($raw -and $raw.Trim()) { $ingJson = $raw | ConvertFrom-Json }
    } catch {
        # ignore - fallback behavior will be used per-domain
        $ingJson = $null
    }

    foreach ($domain in $domainFolders) {
        $domainPath = Join-Path $sslRoot $domain
        $crt = Join-Path $domainPath 'certificate.crt'
        $key = Join-Path $domainPath 'certificate.key'
        if (-not ((Test-Path $crt) -and (Test-Path $key))) {
            Write-Host ("Skipping {0}: certificate.crt or certificate.key not found in {1}" -f $domain, $domainPath) -ForegroundColor Yellow
            continue
        }

        # sanitize a fallback name if needed
        $safeName = ($domain.ToLower() -replace '\.', '-' -replace '[^a-z0-9-]', '-').Trim('-')
        if (-not $safeName) { Write-Host "Skipping invalid domain folder: $domain" -ForegroundColor Yellow; continue }

        $createdAny = $false

        if ($ingJson -and $ingJson.items -and $ingJson.items.Count -gt 0) {
            foreach ($it in $ingJson.items) {
                $ns = $it.metadata.namespace
                $name = $it.metadata.name

                # collect TLS entries and rules hosts
                $tlsEntries = @()
                if ($it.spec -and $it.spec.tls) { $tlsEntries = $it.spec.tls }
                $ruleHosts = @()
                if ($it.spec -and $it.spec.rules) {
                    foreach ($r in $it.spec.rules) { if ($r.host) { $ruleHosts += $r.host } }
                }

                # check if any TLS host matches the folder name, or any rule host matches
                $matched = $false
                if ($tlsEntries.Count -gt 0) {
                    foreach ($t in $tlsEntries) {
                        if ($t.hosts -and ($t.hosts -contains $domain)) {
                            $matched = $true
                            $secretName = $t.secretName
                            break
                        }
                    }
                }
                if (-not $matched -and $ruleHosts -and ($ruleHosts -contains $domain)) {
                    # no TLS block but rules include the host; use a sensible secret name fallback per-namespace
                    $matched = $true
                    # prefer a secret name matching sanitized namespace or domain
                    $secretName = 'tls-' + ($safeName)
                }

                if ($matched) {
                    Write-Host ("- Creating/ensuring secret {0} in namespace {1} for ingress {2}/{3} (from {4})" -f $secretName, $ns, $ns, $name, $domain) -ForegroundColor Cyan
                    kubectl create secret tls $secretName --cert="$crt" --key="$key" -n $ns --dry-run=client -o yaml | kubectl apply -f -
                    if ($LASTEXITCODE -eq 0) { Write-Host ("  -> secret {0} created/updated in {1}" -f $secretName, $ns) -ForegroundColor Green; $createdAny = $true } else { Write-Host ("  -> failed to create secret {0} in {1}" -f $secretName, $ns) -ForegroundColor Yellow }
                }
            }
        }

        if (-not $createdAny) {
            # fallback: create namespace and a tls-<safeName> secret (useful for manual mapping)
            $namespace = $safeName
            $secretName = 'tls-' + $safeName
            Write-Host ("- No matching Ingress found for {0}. Falling back to creating namespace {1} and secret {2}." -f $domain, $namespace, $secretName) -ForegroundColor Yellow
            kubectl create namespace $namespace --dry-run=client -o yaml | kubectl apply -f - > $null 2>&1
            kubectl create secret tls $secretName --cert="$crt" --key="$key" -n $namespace --dry-run=client -o yaml | kubectl apply -f -
            if ($LASTEXITCODE -eq 0) { Write-Host ("  -> secret {0} created/updated in {1}" -f $secretName, $namespace) -ForegroundColor Green } else { Write-Host ("  -> failed to create secret {0} in {1}" -f $secretName, $namespace) -ForegroundColor Yellow }
        }
    }
} else {
    Write-Host ("No ssl/ folder found at {0} - skipping manual SSL secrets." -f $sslRoot) -ForegroundColor Cyan
}

# Copy cert-manager certificates to required namespaces (fallback for missing manual SSL)
Write-Host '7.5. Copying cert-manager certificates to required namespaces...' -ForegroundColor Yellow
$certManagerSecrets = @{
    "api-public-suma-honda-test-tls" = @("suma-ecommerce", "suma-office", "suma-office-general", "suma-android", "suma-pmo", "suma-chat", "suma-webhook", "elasticsearch")
}

foreach ($secretName in $certManagerSecrets.Keys) {
    $targetNamespaces = $certManagerSecrets[$secretName]
    
    # Check if secret exists in cert-manager namespace
    $sourceSecret = kubectl get secret $secretName -n cert-manager --ignore-not-found 2>$null
    if ($sourceSecret) {
        Write-Host ("- Found cert-manager secret: {0}" -f $secretName) -ForegroundColor Cyan
        
        foreach ($targetNs in $targetNamespaces) {
            # Check if namespace exists
            $nsExists = kubectl get namespace $targetNs --ignore-not-found 2>$null
            if ($nsExists) {
                # Check if we need to copy (not if manual SSL exists)
                $manualSslExists = (Test-Path $sslRoot) -and (Test-Path (Join-Path $sslRoot "api.suma-honda.id"))  # adjust domain as needed
                if (-not $manualSslExists) {
                    Write-Host ("  -> Copying {0} to namespace {1}" -f $secretName, $targetNs) -ForegroundColor Cyan
                    try {
                        $secretData = kubectl get secret $secretName -n cert-manager -o json | ConvertFrom-Json
                        $secretData.metadata.namespace = $targetNs
                        $secretData.metadata.PSObject.Properties.Remove('resourceVersion')
                        $secretData.metadata.PSObject.Properties.Remove('uid')
                        $secretData.metadata.PSObject.Properties.Remove('creationTimestamp')
                        $secretData | ConvertTo-Json -Depth 10 | kubectl apply -f - > $null 2>&1
                        if ($LASTEXITCODE -eq 0) {
                            Write-Host ("    ✅ Successfully copied to {0}" -f $targetNs) -ForegroundColor Green
                        } else {
                            Write-Host ("    ❌ Failed to copy to {0}" -f $targetNs) -ForegroundColor Yellow
                        }
                    } catch {
                        Write-Host ("    ❌ Error copying to {0}: {1}" -f $targetNs, $_.Exception.Message) -ForegroundColor Yellow
                    }
                } else {
                    Write-Host ("  -> Skipping {0} (manual SSL exists)" -f $targetNs) -ForegroundColor Yellow
                }
            }
        }
    } else {
        Write-Host ("- cert-manager secret {0} not found - skipping copy" -f $secretName) -ForegroundColor Yellow
    }
}

Write-Host '8. Creating ConfigMaps (if present)...' -ForegroundColor Yellow
Write-Host 'Skipping custom nginx ConfigMap; using ingress controller in cluster.' -ForegroundColor Cyan

# Apply suma-office and suma-office-general ConfigMaps
if (Test-Path 'suma-office/configmap.yaml') { 
    Write-Host 'Applying suma-office ConfigMap...' -ForegroundColor Cyan
    kubectl apply -f suma-office/configmap.yaml 
}
if (Test-Path 'suma-office-general/configmap.yaml') { 
    Write-Host 'Applying suma-office-general ConfigMap...' -ForegroundColor Cyan
    kubectl apply -f suma-office-general/configmap.yaml 
}

if (Test-Path 'monitoring/configmap.yaml') { kubectl apply -f monitoring/configmap.yaml }
if (Test-Path 'monitoring/dashboards') {
    kubectl delete configmap grafana-dashboards -n monitoring --ignore-not-found
    $files = Get-ChildItem -Path 'monitoring/dashboards' -Recurse -File -Include *.json
    $fromFileArgs = $files | ForEach-Object { '--from-file={0}' -f $_.FullName }
    $cmd = 'kubectl create configmap grafana-dashboards -n monitoring ' + ($fromFileArgs -join ' ')
    Invoke-Expression $cmd
    Write-Host 'ConfigMap grafana-dashboards dibuat dari folder dashboards.' -ForegroundColor Green
}

Write-Host '9. Deploying monitoring stack (if present)...' -ForegroundColor Yellow
if (Test-Path 'monitoring/deployment.yaml') { kubectl apply -f monitoring/deployment.yaml }
if (Test-Path 'monitoring/service.yaml') { kubectl apply -f monitoring/service.yaml }

Write-Host '10. Deploying Suma Chat (if present)...' -ForegroundColor Yellow
if (Test-Path 'suma-chat') { kubectl apply -f suma-chat --recursive } else { Write-Host 'Folder suma-chat tidak ditemukan di k8s/ - skipping.' -ForegroundColor Yellow }

Write-Host '11. Deploying Suma Office...' -ForegroundColor Yellow
kubectl apply -f suma-office/deployment.yaml
kubectl apply -f suma-office/service.yaml

Write-Host '11.5. Deploying Suma Office General...' -ForegroundColor Yellow
kubectl apply -f suma-office-general/deployment.yaml
kubectl apply -f suma-office-general/service.yaml

Write-Host '12. Deploying Suma Android...' -ForegroundColor Yellow
kubectl apply -f suma-android/deployment.yaml
kubectl apply -f suma-android/service.yaml

Write-Host '13. Deploying Suma PMO...' -ForegroundColor Yellow
kubectl apply -f suma-pmo/deployment.yaml
kubectl apply -f suma-pmo/service.yaml

Write-Host '14. Deploying Suma Ecommerce...' -ForegroundColor Yellow
kubectl apply -f suma-ecommerce/deployment.yaml
kubectl apply -f suma-ecommerce/service.yaml

Write-Host '15. Checking deployment status...' -ForegroundColor Yellow
kubectl get pods --all-namespaces

Write-Host '16. Service endpoints...' -ForegroundColor Yellow
kubectl get services --all-namespaces

Write-Host '17. Creating PodDisruptionBudgets...' -ForegroundColor Yellow
kubectl apply -f app-pdb.yaml

Write-Host '18. Applying Elasticsearch certs/issuers (if present) and ensuring CA is available...' -ForegroundColor Yellow
$esFolder = Join-Path $PSScriptRoot 'elasticsearch'
if (Test-Path $esFolder) {
    # Apply common cert-manager/issuer/certificate manifests in predictable order
    # simplified filenames in elasticsearch/ (short, predictable)
    $certFiles = @('issuer-selfsigned.yaml','issuer-ca.yaml','ca-cert.yaml','node-cert.yaml')
    foreach ($f in $certFiles) {
        $p = Join-Path $esFolder $f
        if (Test-Path $p) {
            Write-Host ("- Applying {0}" -f $f) -ForegroundColor Cyan
            try { kubectl apply -f $p } catch { Write-Host ("  Warning: failed to apply {0}: {1}" -f $f, $_.Exception.Message) -ForegroundColor Yellow }
        }
    }

    # Wait for CA certificate to become Ready (if present)
    Write-Host '- Waiting for CA certificate (elasticsearch-ca) to become Ready (120s)...' -ForegroundColor Cyan
    try { kubectl wait --for=condition=Ready certificate/elasticsearch-ca -n elasticsearch --timeout=120s; Write-Host '  CA certificate is Ready.' -ForegroundColor Green } catch { Write-Host '  CA certificate did not become Ready within timeout or not present.' -ForegroundColor Yellow }

    # Ensure the CA secret is visible to ClusterIssuer (copy to cert-manager namespace if missing)
    $caSecret = kubectl get secret elasticsearch-ca -n elasticsearch --ignore-not-found -o name 2>$null
    if ($caSecret) {
        $existsInCM = kubectl get secret elasticsearch-ca -n cert-manager --ignore-not-found -o name 2>$null
        if (-not $existsInCM) {
            Write-Host '  Copying elasticsearch-ca secret into namespace cert-manager so ClusterIssuer can use it...' -ForegroundColor Cyan
            try {
                kubectl get secret elasticsearch-ca -n elasticsearch -o yaml | ForEach-Object { $_ -replace 'namespace: elasticsearch','namespace: cert-manager' } | kubectl apply -f -
                Write-Host '  Copied elasticsearch-ca to cert-manager.' -ForegroundColor Green
            } catch { Write-Host ('  Warning: failed to copy elasticsearch-ca to cert-manager: {0}' -f $_.Exception.Message) -ForegroundColor Yellow }
        } else {
            Write-Host '  elasticsearch-ca already present in cert-manager namespace.' -ForegroundColor Cyan
        }
    } else {
        Write-Host '  elasticsearch-ca secret not found in namespace elasticsearch; cert-manager will create it when Certificate is Ready.' -ForegroundColor Yellow
    }

    # Wait for node certificate to be issued (so secret elasticsearch-ssl exists)
    Write-Host "- Waiting for node certificate (elasticsearch-node-cert) to become Ready (120s)..." -ForegroundColor Cyan
    try { kubectl wait --for=condition=Ready certificate/elasticsearch-node-cert -n elasticsearch --timeout=120s; Write-Host '  Node certificate Ready.' -ForegroundColor Green } catch { Write-Host '  Node certificate did not become Ready within timeout.' -ForegroundColor Yellow }
} else {
    Write-Host '  Elasticsearch folder not found; skipping cert-manager apply.' -ForegroundColor Yellow
}

Write-Host '19. Deploying Elasticsearch (StatefulSet)...' -ForegroundColor Yellow
kubectl apply -f elasticsearch/statefulset.yaml
kubectl apply -f elasticsearch/service.yaml

Write-Host '20. Deploying Kibana...' -ForegroundColor Yellow
"# Ensure kibana encryption secret exists (avoid committing raw secrets in repo)" | Out-Null
# Try to apply repository secret manifest if present, otherwise create from a generated literal
$kibanaSecretFile = Join-Path $PSScriptRoot 'kibana\encryption-secret.yaml'
$kibanaSecretExists = kubectl get secret kibana-encryption-key -n kibana --ignore-not-found -o name 2>$null
if (-not $kibanaSecretExists) {
    if (Test-Path $kibanaSecretFile) {
        Write-Host 'Applying kibana/encryption-secret.yaml from repository...' -ForegroundColor Cyan
        try {
            kubectl apply -f $kibanaSecretFile -n kibana
            if ($LASTEXITCODE -eq 0) { Write-Host 'Applied kibana encryption secret from repo.' -ForegroundColor Green }
            else { Write-Host 'Failed to apply kibana encryption secret from repo - will create from literal.' -ForegroundColor Yellow }
        } catch {
            Write-Host 'Error applying repo secret - will create secret from literal.' -ForegroundColor Yellow
        }
    }

    # Re-check; if still not present, create using a generated key
    $kibanaSecretExists = kubectl get secret kibana-encryption-key -n kibana --ignore-not-found -o name 2>$null
    if (-not $kibanaSecretExists) {
    Write-Host 'Creating kibana-encryption-key secret from generated value...' -ForegroundColor Cyan
    # generate a random 32-byte key and base64-encode it
    $bytes = New-Object Byte[] 32
    [System.Security.Cryptography.RNGCryptoServiceProvider]::Create().GetBytes($bytes)
    $rand = [System.Convert]::ToBase64String($bytes)
        kubectl create secret generic kibana-encryption-key -n kibana --from-literal=encryptionKey="$rand" --dry-run=client -o yaml | kubectl apply -f -
        if ($LASTEXITCODE -eq 0) { Write-Host 'kibana-encryption-key secret created.' -ForegroundColor Green } else { Write-Host 'Failed to create kibana-encryption-key secret.' -ForegroundColor Yellow }
    }
} else {
    Write-Host 'kibana-encryption-key secret already exists in namespace kibana.' -ForegroundColor Cyan
}

kubectl apply -f kibana/deployment.yaml -n kibana
kubectl apply -f kibana/service.yaml -n kibana

Write-Host 'Waiting for application pods/services to become Ready before applying Ingress resources...' -ForegroundColor Yellow
# list of namespaces which commonly host apps with ingress in this repo
$appNamespaces = @('suma-chat','suma-office','suma-office-general','suma-android','suma-pmo','suma-ecommerce','kibana','elasticsearch','monitoring')
foreach ($ns in $appNamespaces) {
    $nsExists = kubectl get namespace $ns --ignore-not-found -o name 2>$null
    if (-not $nsExists) { continue }
    Write-Host ("- Waiting for Ready pods in namespace: {0} (timeout 120s)" -f $ns) -ForegroundColor Cyan
    try {
        kubectl wait --for=condition=Ready pods -n $ns --all --timeout=120s >$null 2>&1
        if ($LASTEXITCODE -eq 0) { Write-Host ("  Pods in {0} are Ready." -f $ns) -ForegroundColor Green } else { Write-Host ("  Timeout waiting pods ready in {0} - continuing." -f $ns) -ForegroundColor Yellow }
    } catch {
        Write-Host ("  Warning: error waiting pods in {0}: {1}" -f $ns, $_.Exception.Message) -ForegroundColor Yellow
    }
}

Write-Host 'Applying all ingress.yaml files found in repository (idempotent)...' -ForegroundColor Yellow
$ingressFiles = Get-ChildItem -Path $PSScriptRoot -Recurse -Include 'ingress.yaml' -File -ErrorAction SilentlyContinue

# --- New: apply any Service and Endpoints manifests first so Ingress has backends available ---
Write-Host 'Applying Service and Endpoints manifests before Ingress to avoid timing issues...' -ForegroundColor Yellow
$svcFiles = Get-ChildItem -Path $PSScriptRoot -Recurse -Include 'service.yaml','services.yaml','endpoints.yaml' -File -ErrorAction SilentlyContinue

# First apply any explicit namespace manifests so namespaces exist (e.g. suma-webhook/namespace.yaml)
$nsFiles = Get-ChildItem -Path $PSScriptRoot -Recurse -Include 'namespace.yaml' -File -ErrorAction SilentlyContinue
if ($nsFiles -and $nsFiles.Count -gt 0) {
    foreach ($n in $nsFiles) {
        $reln = $n.FullName.Substring($PSScriptRoot.Length).TrimStart('\','/')
        Write-Host ("- Applying namespace manifest: {0}" -f $reln) -ForegroundColor Cyan
        try { kubectl apply -f $n.FullName } catch { Write-Host ("  Warning: failed to apply namespace {0}: {1}" -f $reln, $_.Exception.Message) -ForegroundColor Yellow }
    }
}

if ($svcFiles -and $svcFiles.Count -gt 0) {
    foreach ($s in $svcFiles) {
        $rel = $s.FullName.Substring($PSScriptRoot.Length).TrimStart('\','/')

        # try to detect namespace in the manifest first
        $text = Get-Content -Path $s.FullName -Raw -ErrorAction SilentlyContinue
        $m = $null
        if ($text) { $m = [regex]::Match($text, 'metadata:\s*?[\r\n]+(?:\s+[^
\n]+[\r\n]+)*?\s+namespace:\s*(\S+)', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase) }
        if ($m -and $m.Success) { $ns = $m.Groups[1].Value.Trim() } else { $ns = $s.Directory.Name }

        if ($ns) {
            Write-Host ("  -> Ensuring namespace exists for {0}: {1}" -f $rel, $ns) -ForegroundColor Cyan
            try { kubectl create namespace $ns --dry-run=client -o yaml | kubectl apply -f - } catch { Write-Host ("  Warning: could not ensure namespace {0}: {1}" -f $ns, $_.Exception.Message) -ForegroundColor Yellow }
        }

        Write-Host ("- Applying service/endpoints manifest: {0}" -f $rel) -ForegroundColor Cyan
        try { kubectl apply -f $s.FullName } catch { Write-Host ("  Warning: failed to apply {0}: {1}" -f $rel, $_.Exception.Message) -ForegroundColor Yellow }
    }
} else {
    Write-Host 'No service or endpoints manifests found to pre-apply.' -ForegroundColor Cyan
}

# Small wait to allow the controller to observe endpoints (helps prevent immediate 503)
Start-Sleep -Seconds 3

if ($ingressFiles -and $ingressFiles.Count -gt 0) {
    foreach ($file in $ingressFiles) {
        $rel = $file.FullName.Substring($PSScriptRoot.Length).TrimStart('\','/')
        Write-Host ("- Preparing to apply ingress: {0}" -f $rel) -ForegroundColor Cyan

        # try to discover namespace from the ingress yaml (metadata.namespace)
        $ns = $null
        try {
            $text = Get-Content -Path $file.FullName -Raw -ErrorAction Stop
            $m = [regex]::Match($text, 'metadata:\s*[\r\n]+(?:\s+[^\r\n]+[\r\n]+)*?\s+namespace:\s*(\S+)', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
            if ($m.Success) { $ns = $m.Groups[1].Value.Trim() }
        } catch {
            # ignore read errors
        }

        # if no namespace in yaml, infer from parent folder name (common pattern)
        if (-not $ns) {
            try { $ns = $file.Directory.Name } catch { $ns = $null }
        }

        if ($ns) {
            Write-Host ("  -> Ensuring namespace exists: {0}" -f $ns) -ForegroundColor Cyan
            try { kubectl create namespace $ns --dry-run=client -o yaml | kubectl apply -f - } catch { Write-Host ("  Warning: could not ensure namespace {0}: {1}" -f $ns, $_.Exception.Message) -ForegroundColor Yellow }
        }

        Write-Host ("- Applying ingress: {0}" -f $rel) -ForegroundColor Cyan
        try {
            kubectl apply -f $file.FullName
        } catch {
            Write-Host ("Warning: kubectl apply failed for {0}: {1}" -f $rel, $_.Exception.Message) -ForegroundColor Yellow
        }
    }
} else {
    Write-Host 'No ingress.yaml files found in repository.' -ForegroundColor Yellow
}

Write-Host 'Production Deployment Complete' -ForegroundColor Green
Write-Host ''
Write-Host 'Access your applications:' -ForegroundColor Cyan
Write-Host '   Localhost: http://localhost' -ForegroundColor White
Write-Host '   Virtual Domain: http://api.suma-honda.id' -ForegroundColor White
Write-Host '   Monitoring: https://monitoring.suma-honda.local' -ForegroundColor White
Write-Host '   Webhook: https://webhook.suma-honda.local' -ForegroundColor White
Write-Host ''
Write-Host 'Kubernetes deployment completed successfully!' -ForegroundColor Green

# Run webhook scheduler script if present
$webhookSchedulerScript = Join-Path $PSScriptRoot 'update\suma-webhook-task-scheduler.ps1'
if (Test-Path $webhookSchedulerScript) { Write-Host 'Menjalankan suma-webhook-task-scheduler.ps1...' -ForegroundColor Cyan; & $webhookSchedulerScript } else { Write-Host 'Script suma-webhook-task-scheduler.ps1 tidak ditemukan.' -ForegroundColor Yellow }

# Run createUserKibanaOnElasticsearch.ps1 if present
$createUserScript = Join-Path $PSScriptRoot 'update\createUserKibanaOnElasticsearch.ps1'
if (Test-Path $createUserScript) { Write-Host 'Menjalankan createUserKibanaOnElasticsearch.ps1...' -ForegroundColor Cyan; & $createUserScript } else { Write-Host 'Script createUserKibanaOnElasticsearch.ps1 tidak ditemukan.' -ForegroundColor Yellow }