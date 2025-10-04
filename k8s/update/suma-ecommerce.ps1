param(
    [string]$Namespace = 'suma-ecommerce',
    [string]$DeploymentName = 'suma-ecommerce-api',
    [string]$ImageName = 'suma-ecommerce-api',
    [string]$Version = 'v1.0.0',
    [string]$ContainerName = '',
    [switch]$NoCache,
    [switch]$NonInteractive
)

Write-Host "=== Suma E-commerce: Build & Redeploy ===" -ForegroundColor Green

function Test-KubeAccess {
    try { kubectl cluster-info | Out-Null; return $true } catch { Write-Host "Error: Kubernetes cluster not accessible." -ForegroundColor Red; return $false }
}

function Test-DockerAccess {
    try { docker version | Out-Null; return $true } catch { Write-Host "Error: Docker tidak tersedia." -ForegroundColor Red; return $false }
}

function Get-Paths {
    $k8sRoot = Split-Path $PSScriptRoot -Parent            # c:\docker\k8s
    $workspaceRoot = Split-Path $k8sRoot -Parent           # c:\docker
    $serviceRoot = Join-Path $workspaceRoot 'suma-ecommerce'
    $dockerfile = Join-Path $serviceRoot 'dockerfile'
    $k8sSvcDir = Join-Path $k8sRoot 'suma-ecommerce'
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

function Apply-EcommerceStack {
    param([string]$Ns, [string]$Dir)
    Ensure-Namespace -Name $Ns
    if (-not (Test-Path $Dir)) { Write-Host "Warning: Folder manifes tidak ditemukan: $Dir" -ForegroundColor Yellow; return }
    Write-Host "Applying Kubernetes manifests..." -ForegroundColor Yellow
    @('namespace.yaml','pvc.yaml','service.yaml','deployment.yaml','hpa.yaml') | ForEach-Object {
        $f = Join-Path $Dir $_
        if (Test-Path $f) { kubectl apply -f $f }
    }
}

function Restart-Deployment {
    param([string]$Ns, [string]$Name)
    Write-Host ("Rollout restart deployment/{0} (ns: {1})" -f $Name, $Ns) -ForegroundColor Yellow
    kubectl rollout restart deployment/$Name -n $Ns
    if ($LASTEXITCODE -ne 0) { Write-Host "Warning: gagal trigger restart." -ForegroundColor Yellow; return }
    kubectl rollout status deployment/$Name -n $Ns --timeout=180s
}

if (-not (Test-DockerAccess)) { return }
if (-not (Test-KubeAccess)) { return }

$paths = Get-Paths

try {
    Build-Image -Name $ImageName -Version $Version -Dockerfile $paths.Dockerfile -Context $paths.Service -NoCache:$NoCache
} catch {
    Write-Host $_ -ForegroundColor Red
    return
}

Apply-EcommerceStack -Ns $Namespace -Dir $paths.Manifests

# If ContainerName not provided, assume it equals the deployment name
if (-not $ContainerName) { $ContainerName = $DeploymentName }

# Build image tag safely and set deployment image so pods will use it
$imageTag = "${ImageName}:$Version"
Write-Host "Updating Deployment image: $DeploymentName -> $imageTag" -ForegroundColor Yellow
kubectl set image deployment/$DeploymentName $ContainerName=$imageTag -n $Namespace
if ($LASTEXITCODE -ne 0) { Write-Host "Warning: kubectl set image failed. Deployment may still use old image if image not pushed to a registry." -ForegroundColor Yellow }

Restart-Deployment -Ns $Namespace -Name $DeploymentName

Write-Host "=== Done ===" -ForegroundColor Green