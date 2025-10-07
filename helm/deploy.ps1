# Suma Platform Deployment Script
# Usage: .\deploy.ps1 [dev|production] [-SkipBuild] [-ForceRecreate]

param(
    [Parameter(Position=0, Mandatory=$true)]
    [ValidateSet('dev', 'production')]
    [string]$Environment,
    
    [switch]$SkipBuild,
    [switch]$ForceRecreate
)

$ErrorActionPreference = "Stop"

# Color functions
function Write-Status {
    param([string]$Message)
    Write-Host "[+] $Message" -ForegroundColor Green
}

function Write-CustomWarning {
    param([string]$Message)
    Write-Host "[!] $Message" -ForegroundColor Yellow
}

function Write-CustomError {
    param([string]$Message)
    Write-Host "[x] $Message" -ForegroundColor Red
    exit 1
}

function Write-Info {
    param([string]$Message)
    Write-Host "[i] $Message" -ForegroundColor Cyan
}

# Set environment-specific values
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ParentDir = Split-Path -Parent $ScriptDir

if ($Environment -eq "dev") {
    $ValuesFile = "values-dev.yaml"
    $ImageTag = "latest"
} else {
    $ValuesFile = "values-production.yaml"
    $ImageTag = "production"
}

# Check prerequisites
function Test-Prerequisites {
    Write-Info "Checking prerequisites..."
    
    if (!(Get-Command kubectl -ErrorAction SilentlyContinue)) {
        Write-CustomError "kubectl is not installed"
    }
    
    if (!(Get-Command helm -ErrorAction SilentlyContinue)) {
        Write-CustomError "helm is not installed"
    }
    
    if (!(Get-Command docker -ErrorAction SilentlyContinue)) {
        Write-CustomError "docker is not installed"
    }
    
    $valuesPath = Join-Path $ScriptDir $ValuesFile
    if (!(Test-Path $valuesPath)) {
        Write-CustomError "Values file not found: $ValuesFile"
    }
    
    Write-Status "All prerequisites met"
}

# Build Docker images
function Build-Images {
    if ($SkipBuild) {
        Write-CustomWarning "Skipping Docker image build"
        return
    }
    
    Write-Status "Building Docker images with tag: $ImageTag"
    
    if (Test-Path "$ParentDir\suma-android") {
        Write-Info "Building suma-android..."
        docker build -t suma-android-api:$ImageTag "$ParentDir\suma-android"
    }
    
    if (Test-Path "$ParentDir\suma-ecommerce") {
        Write-Info "Building suma-ecommerce..."
        docker build -t suma-ecommerce-api:$ImageTag "$ParentDir\suma-ecommerce"
    }
    
    if (Test-Path "$ParentDir\suma-office") {
        Write-Info "Building suma-office..."
        # suma-office has dockerfile.api not dockerfile
        $officeDockerfile = Join-Path "$ParentDir\suma-office" "dockerfile.api"
        if (Test-Path $officeDockerfile) {
            docker build -f $officeDockerfile -t suma-office-api:$ImageTag "$ParentDir\suma-office"
        } else {
            Write-CustomWarning "suma-office dockerfile.api not found"
        }
    }
    
    if (Test-Path "$ParentDir\suma-pmo") {
        Write-Info "Building suma-pmo..."
        docker build -t suma-pmo-api:$ImageTag "$ParentDir\suma-pmo"
    }
    
    if (Test-Path "$ParentDir\suma-chat") {
        Write-Info "Building suma-chat..."
        docker build -t suma-chat:$ImageTag "$ParentDir\suma-chat"
    }
    
    # Suma-webhook runs on host, not in K8s - skip building
    Write-Info "Skipping suma-webhook (runs on host via task scheduler)"
    
    Write-Status "Docker images built successfully"
}

# Setup cert-manager
function Setup-CertManager {
    Write-Status "Checking cert-manager..."
    
    $certManagerYaml = "$ScriptDir\vendor\cert-manager.yaml"
    
    # Check if cert-manager namespace exists
    $namespaceExists = kubectl get namespace cert-manager 2>&1
    $installNeeded = $LASTEXITCODE -ne 0
    
    if ($installNeeded) {
        Write-Info "Installing cert-manager from local file..."
        if (Test-Path $certManagerYaml) {
            kubectl apply -f $certManagerYaml
        } else {
            Write-Warning "Local cert-manager.yaml not found, downloading from GitHub..."
            kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.13.2/cert-manager.yaml
        }
        Write-Info "Waiting for cert-manager to be ready..."
        kubectl wait --for=condition=ready pod --all -n cert-manager --timeout=180s
        Start-Sleep -Seconds 10
        Write-Status "cert-manager is ready"
    } else {
        Write-Status "cert-manager already installed"
        # Verify cert-manager is actually running
        $podsCheck = kubectl get pods -n cert-manager 2>&1
        if ($LASTEXITCODE -ne 0 -or !$podsCheck) {
            Write-Warning "cert-manager namespace exists but no pods found. Reinstalling..."
            kubectl delete namespace cert-manager --ignore-not-found=true
            Start-Sleep -Seconds 5
            if (Test-Path $certManagerYaml) {
                kubectl apply -f $certManagerYaml
            } else {
                kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.13.2/cert-manager.yaml
            }
            Write-Info "Waiting for cert-manager to be ready..."
            kubectl wait --for=condition=ready pod --all -n cert-manager --timeout=180s
            Start-Sleep -Seconds 10
        }
    }
    
    Write-Info "Creating ClusterIssuer..."
    $issuerYaml = @"
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: selfsigned-cluster-issuer
spec:
  selfSigned: {}
"@
    $issuerYaml | kubectl apply -f -
    
    Write-Status "cert-manager setup complete"
}

# Setup CA Issuer for proper certificate DN
function Setup-CAIssuer {
    Write-Status "Setting up CA Issuer with proper Distinguished Name..."
    
    $caIssuerFile = Join-Path $ScriptDir "cluster-issuer-selfsigned.yaml"
    
    if (Test-Path $caIssuerFile) {
        Write-Info "Applying CA Issuer configuration..."
        kubectl apply -f $caIssuerFile
        
        Write-Info "Waiting for CA certificate to be ready..."
        $maxRetries = 30
        $retryCount = 0
        $caReady = $false
        
        while (-not $caReady -and $retryCount -lt $maxRetries) {
            $caCert = kubectl get certificate suma-ca-certificate -n cert-manager -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>$null
            if ($caCert -eq "True") {
                $caReady = $true
                Write-Status "CA certificate is ready"
            } else {
                Start-Sleep -Seconds 2
                $retryCount++
            }
        }
        
        if (-not $caReady) {
            Write-CustomWarning "CA certificate not ready after 60 seconds, continuing anyway..."
        }
        
        # Verify CA Issuer is ready
        $issuerReady = kubectl get clusterissuer suma-ca-issuer -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>$null
        if ($issuerReady -eq "True") {
            Write-Status "CA Issuer (suma-ca-issuer) is ready"
        } else {
            Write-CustomWarning "CA Issuer not ready yet"
        }
    } else {
        Write-CustomWarning "CA Issuer file not found: $caIssuerFile"
    }
}

# Setup metrics-server (optional but recommended)
function Setup-MetricsServer {
    Write-Status "Checking metrics-server..."
    
    $metricsServerYaml = "$ScriptDir\vendor\metrics-server.yaml"
    
    # Check if metrics-server deployment exists
    $deploymentExists = $false
    try {
        $null = kubectl get deployment metrics-server -n kube-system 2>&1
        if ($LASTEXITCODE -eq 0) {
            $deploymentExists = $true
        }
    } catch {
        $deploymentExists = $false
    }
    
    if (-not $deploymentExists) {
        Write-Info "Installing metrics-server from local file..."
        if (Test-Path $metricsServerYaml) {
            kubectl apply -f $metricsServerYaml | Out-Null
            Write-Info "Waiting for metrics-server to be ready (30s timeout)..."
            $null = kubectl wait --for=condition=available deployment/metrics-server -n kube-system --timeout=30s 2>&1
            if ($LASTEXITCODE -eq 0) {
                Write-Status "metrics-server is ready"
            } else {
                Write-Warning "metrics-server may not be ready yet (common in Docker Desktop)."
                Write-Warning "This is optional and won't affect deployment. Continuing..."
            }
        } else {
            Write-Warning "Local metrics-server.yaml not found. Skipping metrics-server installation."
            Write-Warning "This is optional but recommended for resource monitoring."
        }
    } else {
        Write-Status "metrics-server already installed"
    }
}

# Setup ingress-nginx controller
function Setup-IngressNginx {
    Write-Status "Checking ingress-nginx controller..."
    
    $deploymentExists = $false
    try {
        $null = kubectl get deployment ingress-nginx-controller -n ingress-nginx 2>&1
        if ($LASTEXITCODE -eq 0) {
            $deploymentExists = $true
        }
    } catch {
        $deploymentExists = $false
    }
    
    if (-not $deploymentExists) {
        Write-Info "Installing ingress-nginx controller..."
        helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx --force-update 2>$null
        helm install ingress-nginx ingress-nginx/ingress-nginx --namespace ingress-nginx --create-namespace
        
        Write-Info "Waiting for ingress-nginx to be ready (60s timeout)..."
        $null = kubectl wait --for=condition=available deployment/ingress-nginx-controller -n ingress-nginx --timeout=60s 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Status "ingress-nginx controller is ready"
        } else {
            Write-Warning "ingress-nginx controller may not be ready yet."
            Write-Warning "This is required for ingress resources. Continuing..."
        }
    } else {
        Write-Status "ingress-nginx controller already installed"
    }
}

# Create namespaces
function New-Namespaces {
    $namespaces = @(
        "redis",
        "suma-android",
        "suma-ecommerce",
        "suma-office",
        "suma-pmo",
        "suma-chat",
        "suma-webhook",
        "elasticsearch",
        "kibana",
        "monitoring"
    )
    
    Write-Status "Setting up namespaces..."
    
    foreach ($ns in $namespaces) {
        if ($ForceRecreate) {
            Write-Info "Recreating namespace $ns..."
            kubectl delete namespace $ns --ignore-not-found=true 2>$null
            Start-Sleep -Seconds 2
            kubectl create namespace $ns
        } elseif (!(kubectl get namespace $ns 2>$null)) {
            Write-Info "Creating namespace $ns..."
            kubectl create namespace $ns
        } else {
            Write-Status "Namespace $ns already exists"
        }
    }
}

# Generate Grafana dashboard ConfigMaps from JSON files
function Generate-GrafanaDashboards {
    Write-Info "Generating Grafana dashboard ConfigMaps from JSON files..."
    
    $dashboardsDir = Join-Path $ScriptDir "charts\monitoring\dashboards"
    $templatesDir = Join-Path $ScriptDir "charts\monitoring\templates"
    $outputFile = Join-Path $templatesDir "grafana-dashboards.yaml"
    
    if (!(Test-Path $dashboardsDir)) {
        Write-CustomWarning "Dashboards directory not found: $dashboardsDir"
        return
    }
    
    # Get all JSON files recursively
    $jsonFiles = Get-ChildItem -Path $dashboardsDir -Filter "*.json" -Recurse
    
    if ($jsonFiles.Count -eq 0) {
        Write-CustomWarning "No dashboard JSON files found in $dashboardsDir"
        return
    }
    
    Write-Info "Found $($jsonFiles.Count) dashboard files"
    
    # Start building the ConfigMap YAML
    $yaml = @"
{{- if .Values.configMap.dashboards.enabled }}
apiVersion: v1
kind: ConfigMap
metadata:
  name: {{ include "monitoring.fullname" . }}-grafana-dashboards
  labels:
    {{- include "monitoring.labels" . | nindent 4 }}
    grafana_dashboard: "1"
data:
"@
    
    # Add each JSON file as a data entry
    foreach ($file in $jsonFiles) {
        $fileName = $file.Name
        $content = Get-Content $file.FullName -Raw
        
        # Escape Helm template syntax in JSON content
        # Use placeholders to avoid nested replacements
        $step1 = $content -replace '\{\{', '__DOUBLE_OPEN__'
        $step2 = $step1 -replace '\}\}', '__DOUBLE_CLOSE__'
        $step3 = $step2 -replace '__DOUBLE_OPEN__', '{{ "{{" }}'
        $escaped = $step3 -replace '__DOUBLE_CLOSE__', '{{ "}}" }}'
        
        # Add 4-space indentation to each line for YAML
        $lines = $escaped -split "`n"
        $indentedLines = $lines | ForEach-Object { "    $_" }
        $escapedContent = $indentedLines -join "`n"
        
        Write-Info "  Adding dashboard: $fileName"
        
        $yaml += @"

  $fileName`: |
$escapedContent
"@
    }
    
    # Close the ConfigMap
    $yaml += @"

{{- end }}
"@
    
    # Write to file
    Set-Content -Path $outputFile -Value $yaml -Force
    Write-Status "Generated grafana-dashboards.yaml with $($jsonFiles.Count) dashboards"
}

# Deploy Helm charts
function Deploy-Charts {
    Write-Status "Deploying Helm charts for $Environment environment..."
    
    Set-Location $ScriptDir
    
    Write-Info "Updating Helm dependencies..."
    helm dependency update .
    
    # Deploy in specific order with dependencies
    # Phase 1: Infrastructure (Redis, Elasticsearch)
    $phase1Charts = @(
        @{name="redis-cluster"; namespace="redis"},
        @{name="elasticsearch"; namespace="elasticsearch"}
    )
    
    Write-Info "Phase 1: Deploying infrastructure (Redis, Elasticsearch)..."
    foreach ($chart in $phase1Charts) {
        $chartName = $chart.name
        $namespace = $chart.namespace
        $chartPath = ".\charts\$chartName"
        
        if (!(Test-Path $chartPath)) {
            Write-CustomWarning "Chart not found: $chartPath"
            continue
        }
        
        if (helm list -n $namespace | Select-String $chartName) {
            Write-Info "Upgrading $chartName in namespace $namespace..."
            helm upgrade $chartName $chartPath -n $namespace -f $ValuesFile --create-namespace --timeout 5m
        } else {
            Write-Info "Installing $chartName in namespace $namespace..."
            helm install $chartName $chartPath -n $namespace -f $ValuesFile --create-namespace --timeout 5m
        }
    }
    
    # Wait for Elasticsearch to be ready before proceeding
    Write-Info "Waiting for Elasticsearch to be ready (this may take 3-5 minutes)..."
    kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=elasticsearch -n elasticsearch --timeout=600s 2>$null
    if ($LASTEXITCODE -eq 0) {
        Write-Status "Elasticsearch is ready"
    } else {
        Write-CustomWarning "Elasticsearch pods may not be ready yet, but continuing..."
    }
    
    # Phase 3: Deploy Kibana and other services
    $phase2Charts = @(
        @{name="kibana"; namespace="kibana"},
        @{name="suma-android"; namespace="suma-android"},
        @{name="suma-ecommerce"; namespace="suma-ecommerce"},
        @{name="suma-office"; namespace="suma-office"},
        @{name="suma-pmo"; namespace="suma-pmo"},
        @{name="suma-chat"; namespace="suma-chat"},
        @{name="suma-webhook"; namespace="suma-webhook"},
        @{name="monitoring"; namespace="monitoring"}
    )
    
    Write-Info "Phase 3: Deploying applications (Kibana, Apps, Monitoring)..."
    Write-Info "Note: suma-webhook chart only creates Service/Endpoints/Ingress (webhook runs on host)"
    
    foreach ($chart in $phase2Charts) {
        $chartName = $chart.name
        $namespace = $chart.namespace
        $chartPath = ".\charts\$chartName"
        
        if (!(Test-Path $chartPath)) {
            Write-CustomWarning "Chart not found: $chartPath"
            continue
        }
        
        if (helm list -n $namespace | Select-String $chartName) {
            Write-Info "Upgrading $chartName in namespace $namespace..."
            helm upgrade $chartName $chartPath -n $namespace -f $ValuesFile --create-namespace --timeout 5m
        } else {
            Write-Info "Installing $chartName in namespace $namespace..."
            helm install $chartName $chartPath -n $namespace -f $ValuesFile --create-namespace --timeout 5m
        }
        
        # Special handling for Kibana: create user after deployment
        if ($chartName -eq "kibana") {
            Write-Status "Kibana deployed - user creation will be done at the end of deployment"
        }
    }
    
    Write-Status "All charts deployed successfully"
}

# Setup Kibana user in Elasticsearch
function Setup-KibanaUser {
    Write-Status "Setting up Kibana user in Elasticsearch..."
    
    $kibanaUserScript = Join-Path $ScriptDir "perintah\create-kibana-user.ps1"
    
    if (Test-Path $kibanaUserScript) {
        Write-Info "Running Kibana user creation script..."
        
        # Use external domain for user creation
        if ($Environment -eq "dev") {
            $esDomain = "search.suma-honda.local"
        } else {
            $esDomain = "search.suma-honda.id"
        }
        
        # Wait for Elasticsearch service to be ready first
        Write-Info "Waiting for Elasticsearch service to be ready..."
        $esWaitTimeout = 180
        $esWaitElapsed = 0
        $esReady = $false
        
        while (-not $esReady -and $esWaitElapsed -lt $esWaitTimeout) {
            try {
                # Check if pod is ready using kubectl
                $podStatus = kubectl get pods -n elasticsearch -l app.kubernetes.io/name=elasticsearch -o jsonpath='{.items[0].status.phase}' 2>&1
                if ($podStatus -eq "Running") {
                    # Check if port 9200 is responding
                    $response = kubectl exec -n elasticsearch elasticsearch-0 -- curl -s -o /dev/null -w "%{http_code}" http://localhost:9200 2>&1
                    if ($response -eq "200" -or $response -eq "401") {
                        $esReady = $true
                        Write-Status "Elasticsearch is ready!"
                        break
                    }
                }
            } catch {
                # Continue waiting
            }
            
            $remaining = $esWaitTimeout - $esWaitElapsed
            Write-Host "  Checking Elasticsearch... (remaining: $remaining seconds)" -ForegroundColor Gray
            Start-Sleep -Seconds 5
            $esWaitElapsed += 5
        }
        
        if (-not $esReady) {
            Write-CustomWarning "Elasticsearch not ready after ${esWaitTimeout}s"
            Write-Info "Skipping Kibana user creation - you can run manually: $kibanaUserScript"
            return
        }
        
            # Run the script with external domain
            & $kibanaUserScript `
                -ElasticsearchDomain $esDomain `
                -ElasticsearchUser "elastic" `
                -ElasticsearchPass "admin123" `
                -KibanaUserName "kibana_user" `
                -KibanaUserPass "kibanapass" `
                -MaxWaitSeconds 60
            
            if ($LASTEXITCODE -eq 0) {
                Write-Status "Kibana user created successfully"
            } else {
                Write-CustomWarning "Kibana user creation had issues (exit code: $LASTEXITCODE)"
                Write-Info "Kibana may not connect to Elasticsearch properly"
            }
        } catch {
            Write-CustomWarning "Failed to create Kibana user: $_"
            Write-Info "You can create it manually: $kibanaUserScript"
        }
    } else {
        Write-CustomWarning "Kibana user script not found: $kibanaUserScript"
        Write-Info "Kibana may not be able to connect to Elasticsearch"
    }
}

# Setup webhook task scheduler on host
function Setup-WebhookTaskScheduler {
    Write-Status "Setting up suma-webhook task scheduler on host..."
    
    $webhookSchedulerScript = Join-Path $ScriptDir "perintah\setup-webhook-scheduler.ps1"
    
    if (Test-Path $webhookSchedulerScript) {
        Write-Info "Running webhook task scheduler setup..."
        Write-Info "This requires Administrator privileges..."
        try {
            # Check if already running as admin
            $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
            
            if ($isAdmin) {
                & $webhookSchedulerScript
                Write-Status "Webhook task scheduler configured successfully"
            } else {
                Write-Info "Requesting Administrator elevation for webhook setup..."
                
                # Ask user for confirmation
                Write-Host ""
                Write-Host "╔════════════════════════════════════════════════════════╗" -ForegroundColor Yellow
                Write-Host "║  Administrator Privileges Required                     ║" -ForegroundColor Yellow
                Write-Host "╚════════════════════════════════════════════════════════╝" -ForegroundColor Yellow
                Write-Host ""
                Write-Host "Webhook setup requires Administrator privileges." -ForegroundColor White
                Write-Host "This will open a UAC prompt to run:" -ForegroundColor Gray
                Write-Host "  $webhookSchedulerScript" -ForegroundColor Gray
                Write-Host ""
                
                # Force output before Read-Host
                [Console]::Out.Flush()
                
                $confirmation = Read-Host "Do you want to elevate and run webhook setup? (Y/N)"
                
                if ($confirmation -eq 'Y' -or $confirmation -eq 'y') {
                    Write-Host ""
                    Write-Host "Opening UAC prompt..." -ForegroundColor Yellow
                    # Run with elevation
                    Start-Process powershell -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$webhookSchedulerScript`"" -Wait
                    Write-Status "Webhook task scheduler setup completed"
                } else {
                    Write-Host ""
                    Write-Info "Skipping webhook setup - you can run it manually later:"
                    Write-Host "  Start-Process powershell -Verb RunAs -ArgumentList `"-File '$webhookSchedulerScript'`"" -ForegroundColor Gray
                }
            }
        } catch {
            Write-CustomWarning "Failed to setup webhook task scheduler: $_"
            Write-Info "You can run it manually: $webhookSchedulerScript"
        }
    } else {
        Write-CustomWarning "Webhook scheduler script not found: $webhookSchedulerScript"
    }
}

# Wait for pods
function Wait-ForPods {
    $namespaces = @(
        "redis",
        "suma-android",
        "suma-ecommerce",
        "suma-office",
        "suma-pmo",
        "suma-chat",
        "suma-webhook",
        "elasticsearch",
        "kibana",
        "monitoring"
    )
    
    Write-Status "Waiting for pods to be ready..."
    
    foreach ($ns in $namespaces) {
        Write-Info "Checking pods in namespace $ns..."
        kubectl wait --for=condition=ready pod --all -n $ns --timeout=120s 2>$null
    }
}

# Show deployment status
function Show-Status {
    Write-Host ""
    Write-Host ("=" * 80) -ForegroundColor Cyan
    Write-Status "Deployment Status for $Environment Environment"
    Write-Host ("=" * 80) -ForegroundColor Cyan
    Write-Host ""
    
    $namespaces = @(
        "redis",
        "suma-android",
        "suma-ecommerce",
        "suma-office",
        "suma-pmo",
        "suma-chat",
        "suma-webhook",
        "elasticsearch",
        "kibana",
        "monitoring"
    )
    
    foreach ($ns in $namespaces) {
        Write-Host "Namespace: $ns" -ForegroundColor Yellow
        Write-Host "Pods:" -ForegroundColor Cyan
        kubectl get pods -n $ns 2>$null | Out-String | Write-Host
    }
}

# Show access URLs
function Show-URLs {
    Write-Host ""
    Write-Host ("=" * 80) -ForegroundColor Cyan
    Write-Status "Access URLs - $Environment Environment"
    Write-Host ("=" * 80) -ForegroundColor Cyan
    Write-Host ""
    
    if ($Environment -eq "dev") {
        Write-Host "  Applications:" -ForegroundColor Cyan
        Write-Host "    - Suma Android:    http://suma-android.local" -ForegroundColor White
        Write-Host "    - Suma E-commerce: http://suma-ecommerce.local" -ForegroundColor White
        Write-Host "    - Suma Office:     http://suma-office.local" -ForegroundColor White
        Write-Host "    - Suma PMO:        http://suma-pmo.local" -ForegroundColor White
        Write-Host "    - Suma Chat:       http://suma-chat.local" -ForegroundColor White
        Write-Host ""
        Write-Host "  Infrastructure:" -ForegroundColor Cyan
        Write-Host "    - Redis:           redis-cluster.redis.svc.cluster.local:6379" -ForegroundColor White
        Write-Host "    - Elasticsearch:   http://search.suma-honda.local" -ForegroundColor White
        Write-Host "    - Kibana:          http://kibana.suma-honda.local" -ForegroundColor White
        Write-Host "    - Monitoring:      http://monitoring.suma-honda.local" -ForegroundColor White
        Write-Host "    - Webhook (Host):  http://192.168.1.125:5000 (direct)" -ForegroundColor White
        Write-Host "                       http://webhook.suma-honda.local (via K8s)" -ForegroundColor White
        Write-Host ""
        Write-Host "  API Gateway:" -ForegroundColor Cyan
        Write-Host "    - API Base:        http://api.suma-honda.id" -ForegroundColor White
        Write-Host "    - Android API:     http://api.suma-honda.id/android" -ForegroundColor White
        Write-Host "    - E-commerce API:  http://api.suma-honda.id/ecommerce" -ForegroundColor White
        Write-Host "    - Office API:      http://api.suma-honda.id/office" -ForegroundColor White
        Write-Host "    - PMO API:         http://api.suma-honda.id/pmo" -ForegroundColor White
        Write-Host "    - Chat API:        http://api.suma-honda.id/chat" -ForegroundColor White
        Write-Host ""
        Write-CustomWarning "Note: Add these entries to C:\Windows\System32\drivers\etc\hosts:"
        Write-Host "  127.0.0.1 suma-android.local suma-ecommerce.local suma-office.local" -ForegroundColor Gray
        Write-Host "  127.0.0.1 suma-pmo.local suma-chat.local" -ForegroundColor Gray
        Write-Host "  127.0.0.1 search.suma-honda.local kibana.suma-honda.local monitoring.suma-honda.local" -ForegroundColor Gray
        Write-Host "  127.0.0.1 api.suma-honda.id webhook.suma-honda.local" -ForegroundColor Gray
    } else {
        Write-Host "  Applications:" -ForegroundColor Cyan
        Write-Host "    - Suma Android:    https://suma-android.suma-honda.id" -ForegroundColor White
        Write-Host "    - Suma E-commerce: https://suma-ecommerce.suma-honda.id" -ForegroundColor White
        Write-Host "    - Suma Office:     https://suma-office.suma-honda.id" -ForegroundColor White
        Write-Host "    - Suma PMO:        https://suma-pmo.suma-honda.id" -ForegroundColor White
        Write-Host "    - Suma Chat:       https://suma-chat.suma-honda.id" -ForegroundColor White
        Write-Host ""
        Write-Host "  Infrastructure:" -ForegroundColor Cyan
        Write-Host "    - Redis:           redis-cluster.redis.svc.cluster.local:6379" -ForegroundColor White
        Write-Host "    - Elasticsearch:   https://search.suma-honda.id" -ForegroundColor White
        Write-Host "    - Kibana:          https://kibana.suma-honda.id" -ForegroundColor White
        Write-Host "    - Monitoring:      https://monitoring.suma-honda.id" -ForegroundColor White
        Write-Host "    - Webhook (Host):  https://192.168.1.125:5000 (direct)" -ForegroundColor White
        Write-Host "                       https://webhook.suma-honda.id (via K8s)" -ForegroundColor White
        Write-Host ""
        Write-Host "  API Gateway:" -ForegroundColor Cyan
        Write-Host "    - API Base:        https://api.suma-honda.id" -ForegroundColor White
        Write-Host "    - Android API:     https://api.suma-honda.id/android" -ForegroundColor White
        Write-Host "    - E-commerce API:  https://api.suma-honda.id/ecommerce" -ForegroundColor White
        Write-Host "    - Office API:      https://api.suma-honda.id/office" -ForegroundColor White
        Write-Host "    - PMO API:         https://api.suma-honda.id/pmo" -ForegroundColor White
        Write-Host "    - Chat API:        https://api.suma-honda.id/chat" -ForegroundColor White
    }
    Write-Host ""
}

# Main execution
$ErrorActionPreference = "Continue"  # Continue on non-terminating errors
try {
    Write-Host ""
    Write-Host ("=" * 80) -ForegroundColor Cyan
    Write-Status "Suma Platform Deployment Script"
    Write-Info "Environment: $Environment"
    Write-Info "Values File: $ValuesFile"
    Write-Info "Image Tag:   $ImageTag"
    Write-Host ("=" * 80) -ForegroundColor Cyan
    Write-Host ""
    
    Test-Prerequisites
    Build-Images
    Setup-CertManager
    Setup-CAIssuer
    Setup-MetricsServer
    Setup-IngressNginx
    New-Namespaces
    Setup-WebhookTaskScheduler
    Generate-GrafanaDashboards
    Deploy-Charts
    Setup-KibanaUser
    Wait-ForPods
    Show-Status
    Show-URLs
    
    Write-Host ""
    Write-Host ("=" * 80) -ForegroundColor Green
    Write-Status "Deployment Complete!"
    Write-Host ("=" * 80) -ForegroundColor Green
    Write-Host ""
} catch {
    Write-CustomError "Deployment failed: $_"
}
