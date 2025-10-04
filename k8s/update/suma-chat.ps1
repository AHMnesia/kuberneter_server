#
# suma-chat.ps1
# Smart build & deploy helper for the Socket.IO chat service.
# Mirrors the capabilities of the suma-office tooling (build/versioning,
# optional dry-run, selective build/deploy) while preserving the existing
# rolling-update behaviour.
#

[CmdletBinding()]
param(
	[string]$Namespace = "suma-chat",
	[string]$Context,
	[string]$Version = "v1.0.0",
	[switch]$NoCache,
	[switch]$BuildOnly,
	[switch]$DeployOnly,
	[switch]$DryRun,
	[switch]$SkipRolloutStatus,
	[string]$KubectlPath = "kubectl",
	[string]$DockerPath = "docker"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if ($BuildOnly -and $DeployOnly) {
	throw "BuildOnly and DeployOnly cannot be used together."
}

function Test-KubeAccess {
	try {
		& $KubectlPath cluster-info | Out-Null
		return $true
	} catch {
		Write-Host "Error: Kubernetes cluster not accessible." -ForegroundColor Red
		return $false
	}
}

function Test-DockerAccess {
	if ($DeployOnly) { return $true }
	try {
		& $DockerPath version | Out-Null
		return $true
	} catch {
		Write-Host "Error: Docker not available." -ForegroundColor Red
		return $false
	}
}

function Get-Paths {
	$k8sRoot = Split-Path $PSScriptRoot -Parent
	$workspaceRoot = Split-Path $k8sRoot -Parent
	$serviceRoot = Join-Path $workspaceRoot 'suma-chat'
	$dockerfile = Join-Path $serviceRoot 'dockerfile'
	$manifests = Join-Path $k8sRoot 'suma-chat'
	return @{ Workspace=$workspaceRoot; K8s=$k8sRoot; Service=$serviceRoot; Dockerfile=$dockerfile; Manifests=$manifests }
}

$paths = Get-Paths
if (-not (Test-Path $paths.Manifests)) {
	throw "Manifests directory not found: $($paths.Manifests)"
}

$manifestsRoot = $paths.Manifests
$contextLabel = if ([string]::IsNullOrWhiteSpace($Context)) { '(default)' } else { $Context }
$modeLabel = if ($BuildOnly) { 'Build only' } elseif ($DeployOnly) { 'Deploy only' } else { 'Build + Deploy' }

Write-Host "=== Suma Chat: Smart Build & Deploy ===" -ForegroundColor Green
Write-Host "Namespace : $Namespace" -ForegroundColor Cyan
Write-Host "Kube Ctx  : $contextLabel" -ForegroundColor Cyan
Write-Host "Version   : $Version" -ForegroundColor Cyan
Write-Host "Mode      : $modeLabel" -ForegroundColor Yellow
Write-Host "Dry Run   : $DryRun" -ForegroundColor Yellow

function Invoke-Kubectl {
	param(
		[string[]]$Arguments,
		[switch]$UseNamespace
	)

	if (-not $Arguments -or $Arguments.Count -eq 0) {
		throw 'Invoke-Kubectl requires at least one argument.'
	}

	$argsList = @()
	if ($UseNamespace) {
		$argsList += @('-n', $Namespace)
	}
	$argsList += $Arguments

	$display = "$KubectlPath $($argsList -join ' ')"
	if ($DryRun) {
		Write-Host "[DRY-RUN] $display" -ForegroundColor Yellow
		return
	}

	Write-Host "→ $display" -ForegroundColor Cyan
	& $KubectlPath @argsList
	if ($LASTEXITCODE -ne 0) {
		throw "kubectl exited with code $LASTEXITCODE"
	}
}

function Invoke-ChatManifests {
	$namespaceFile = Join-Path $manifestsRoot 'namespace.yaml'
	if (Test-Path $namespaceFile) {
		Invoke-Kubectl -Arguments @('apply', '-f', $namespaceFile)
	}

	$manifestFiles = Get-ChildItem -Path $manifestsRoot -Filter '*.yaml' -File |
		Where-Object { $_.Name -ne 'namespace.yaml' }

	foreach ($file in $manifestFiles) {
		Invoke-Kubectl -Arguments @('apply', '-f', $file.FullName) -UseNamespace
	}
}

function Invoke-BuildChatImage {
	param(
		[string]$ImageName,
		[string]$Version,
		[string]$Dockerfile,
		[string]$Context,
		[switch]$NoCache
	)

	if ($DryRun) {
		Write-Host "[DRY-RUN] docker build -t ${ImageName}:${Version} -f $Dockerfile $Context" -ForegroundColor Yellow
		return
	}

	if (-not (Test-Path $Dockerfile)) {
		throw "Dockerfile not found: $Dockerfile"
	}

	$versionTag = "{0}:{1}" -f $ImageName, $Version
	$latestTag = "{0}:latest" -f $ImageName
	Write-Host "Building image: $versionTag" -ForegroundColor Magenta
	$dockerArgs = @('build', '-t', $versionTag, '-f', $Dockerfile)
	if ($NoCache.IsPresent) { $dockerArgs += '--no-cache' }
	$dockerArgs += $Context
	& $DockerPath @dockerArgs
	if ($LASTEXITCODE -ne 0) {
		throw "Docker build failed for $versionTag"
	}

	Write-Host "Tagging $versionTag as $latestTag" -ForegroundColor Magenta
	& $DockerPath tag $versionTag $latestTag
	if ($LASTEXITCODE -ne 0) {
		throw "Docker tag failed for $latestTag"
	}
}

if (-not (Test-DockerAccess)) { return }
if (-not (Test-KubeAccess)) { return }

try {
	if ($Context) {
		Invoke-Kubectl -Arguments @('config', 'use-context', $Context)
	}

	$imageName = 'suma-chat'
	$imageTag = "{0}:{1}" -f $imageName, $Version

	if (-not $DeployOnly) {
		Write-Host "=== BUILD PHASE ===" -ForegroundColor Green
		Invoke-BuildChatImage -ImageName $imageName -Version $Version -Dockerfile $paths.Dockerfile -Context $paths.Service -NoCache:$NoCache
		if (-not $DryRun) {
			Write-Host "Build completed successfully" -ForegroundColor Green
		}
	}

	if (-not $BuildOnly) {
		Write-Host "=== DEPLOY PHASE ===" -ForegroundColor Green
		Invoke-ChatManifests
		$shouldRestart = -not $DeployOnly
		if ($shouldRestart) {
			Invoke-Kubectl -Arguments @('rollout', 'restart', 'deployment/suma-chat') -UseNamespace
		} else {
			Write-Host "Skip rollout restart (DeployOnly mode)" -ForegroundColor Yellow
		}

		if (-not $SkipRolloutStatus) {
			Invoke-Kubectl -Arguments @('rollout', 'status', 'deployment/suma-chat', '--timeout=180s') -UseNamespace
		}

		Invoke-Kubectl -Arguments @('get', 'pods', '-o', 'wide') -UseNamespace
	}

	Write-Host "=== COMPLETED ===" -ForegroundColor Green
	Write-Host "Image    : $imageTag" -ForegroundColor White
	Write-Host "Manifest : $manifestsRoot" -ForegroundColor White
} catch {
	Write-Host "Suma-chat update failed: $($_.Exception.Message)" -ForegroundColor Red
	throw
}
