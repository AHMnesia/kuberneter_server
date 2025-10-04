param(
    [ValidateSet('office', 'general', 'both')]
    [string]$Service = 'both',
    [string]$Version = 'v1.0.0',
    [switch]$NoCache,
    [switch]$BuildOnly,
    [switch]$DeployOnly
)

Write-Host "=== Suma Office: Smart Build & Deploy ===" -ForegroundColor Green
Write-Host "Service: $Service | Version: $Version" -ForegroundColor Cyan
if ($BuildOnly) { Write-Host "Mode: Build Only" -ForegroundColor Yellow }
elseif ($DeployOnly) { Write-Host "Mode: Deploy Only" -ForegroundColor Yellow }
else { Write-Host "Mode: Build + Deploy" -ForegroundColor Yellow }

function Test-KubeAccess {
    try { kubectl cluster-info | Out-Null; return $true } catch { Write-Host "Error: Kubernetes cluster not accessible." -ForegroundColor Red; return $false }
}

function Test-DockerAccess {
    try { docker version | Out-Null; return $true } catch { Write-Host "Error: Docker tidak tersedia." -ForegroundColor Red; return $false }
}

function Get-Paths {
    $k8sRoot = Split-Path $PSScriptRoot -Parent            # c:\docker\k8s
    $workspaceRoot = Split-Path $k8sRoot -Parent           # c:\docker
    $serviceRoot = Join-Path $workspaceRoot 'suma-office'
    $dockerfile = Join-Path $serviceRoot 'dockerfile.api'
    $k8sSvcDir = Join-Path $k8sRoot 'suma-office'
    return @{ Workspace=$workspaceRoot; K8s=$k8sRoot; Service=$serviceRoot; Dockerfile=$dockerfile; Manifests=$k8sSvcDir }
}

function Ensure-Namespace {
    param([string]$Name)
    kubectl create namespace $Name --dry-run=client -o yaml | kubectl apply -f - | Out-Null
}

function Build-Image {
    param([string]$Name, [string]$Version, [string]$Dockerfile, [string]$Context, [switch]$NoCache)
    if (-not (Test-Path $Dockerfile)) { throw "Dockerfile not found: $Dockerfile" }
    $versionTag = "{0}:{1}" -f $Name, $Version
    $latestTag = "{0}:latest" -f $Name
    Write-Host ("Building image: {0}" -f $versionTag) -ForegroundColor Yellow
    $args = @('build', '-t', $versionTag, '-f', $Dockerfile)
    if ($NoCache.IsPresent) { $args += '--no-cache' }
    $args += $Context
    & docker @args
    if ($LASTEXITCODE -ne 0) { throw "Docker build failed for $versionTag" }

    Write-Host ("Tagging {0} as {1}" -f $versionTag, $latestTag) -ForegroundColor Yellow
    & docker tag $versionTag $latestTag
    if ($LASTEXITCODE -ne 0) { throw "Docker tag failed for $latestTag" }
}

function Apply-ServiceStack {
    param([string]$Ns, [string]$Dir, [string]$ServiceName)
    Ensure-Namespace -Name $Ns
    if (-not (Test-Path $Dir)) { Write-Host "Warning: Folder manifests tidak ditemukan: $Dir" -ForegroundColor Yellow; return }
    Write-Host "Applying $ServiceName Kubernetes manifests..." -ForegroundColor Yellow
    
    # Simple apply like deploy.ps1 - apply all files in directory
    kubectl apply -f $Dir
    if ($LASTEXITCODE -eq 0) {
        Write-Host "$ServiceName manifests applied successfully!" -ForegroundColor Green
    } else {
        Write-Host "Warning: Some manifests may have failed to apply for $ServiceName" -ForegroundColor Yellow
    }
}

function Deploy-Service {
    param([string]$ServiceType, [string]$ImageTag, [string]$Version, [switch]$RestartPods)
    
    $configs = @{
        'office' = @{
            Namespace = 'suma-office'
            DeploymentName = 'suma-office-api'
            ManifestsDir = Join-Path (Get-Paths).K8s 'suma-office'
            ServiceName = 'Suma Office'
        }
        'general' = @{
            Namespace = 'suma-office-general'  
            DeploymentName = 'suma-office-general-api'
            ManifestsDir = Join-Path (Get-Paths).K8s 'suma-office-general'
            ServiceName = 'Suma Office General'
        }
    }
    
    $config = $configs[$ServiceType]
    Write-Host "Deploying $($config.ServiceName)..." -ForegroundColor Green
    
    # Simple apply like deploy.ps1 - no rollout waiting
    Apply-ServiceStack -Ns $config.Namespace -Dir $config.ManifestsDir -ServiceName $config.ServiceName
    
    # If we built a new image, restart deployment to pull latest image
    if ($RestartPods) {
        Write-Host "Restarting deployment to use latest image..." -ForegroundColor Yellow
        kubectl rollout restart deployment/$($config.DeploymentName) -n $config.Namespace
        if ($LASTEXITCODE -eq 0) {
            Write-Host "Waiting for rollout to complete..." -ForegroundColor Yellow
            kubectl rollout status deployment/$($config.DeploymentName) -n $config.Namespace --timeout=300s
            if ($LASTEXITCODE -eq 0) {
                Write-Host "Deployment completed successfully!" -ForegroundColor Green
            } else {
                Write-Host "Warning: Rollout may still be in progress or failed" -ForegroundColor Yellow
            }
        } else {
            Write-Host "Warning: Failed to restart deployment" -ForegroundColor Yellow
        }
    }
    
    Write-Host "$($config.ServiceName) deployment applied successfully!" -ForegroundColor Green
}

# Removed complex restart function - using simple apply like deploy.ps1

if (-not (Test-DockerAccess)) { return }
if (-not (Test-KubeAccess)) { return }

# Main execution
$paths = Get-Paths
$imageName = 'suma-office-api'
$imageTag = "${imageName}:$Version"

# Build phase
if (-not $DeployOnly) {
    Write-Host "=== BUILD PHASE ===" -ForegroundColor Magenta
    try {
        Build-Image -Name $imageName -Version $Version -Dockerfile $paths.Dockerfile -Context $paths.Service -NoCache:$NoCache
        Write-Host "Build completed successfully!" -ForegroundColor Green
    } catch {
        Write-Host "Build failed: $_" -ForegroundColor Red
        return
    }
}

# Deploy phase
if (-not $BuildOnly) {
    Write-Host "=== DEPLOY PHASE ===" -ForegroundColor Magenta
    
    # Determine if we should restart pods (if we just built new image)
    $shouldRestart = -not $DeployOnly
    
    switch ($Service) {
        'office' {
            Write-Host "Deploying ONLY suma-office..." -ForegroundColor Cyan
            Deploy-Service -ServiceType 'office' -ImageTag $imageTag -Version $Version -RestartPods:$shouldRestart
        }
        'general' {
            Write-Host "Deploying ONLY suma-office-general..." -ForegroundColor Cyan  
            Deploy-Service -ServiceType 'general' -ImageTag $imageTag -Version $Version -RestartPods:$shouldRestart
        }
        'both' {
            Write-Host "Deploying BOTH services..." -ForegroundColor Cyan
            Deploy-Service -ServiceType 'office' -ImageTag $imageTag -Version $Version -RestartPods:$shouldRestart
            Deploy-Service -ServiceType 'general' -ImageTag $imageTag -Version $Version -RestartPods:$shouldRestart
        }
    }
}

Write-Host "=== COMPLETED ===" -ForegroundColor Green
Write-Host "Service(s) processed: $Service" -ForegroundColor White
Write-Host "Image: $imageTag" -ForegroundColor White