# Suma Webhook Task Scheduler Setup Script (Windows)
# Usage: .\setup-webhook-scheduler.ps1
# Note: Must run as Administrator

param(
    [switch]$Uninstall
)

$ErrorActionPreference = "Stop"

# Check if running as administrator
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "[ERROR] Script must be run as Administrator" -ForegroundColor Red
    Write-Host "Right-click PowerShell and select 'Run as Administrator', then run this script again" -ForegroundColor Yellow
    exit 1
}

# Paths
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$HelmDir = Split-Path -Parent $ScriptDir
$RootDir = Split-Path -Parent $HelmDir
$WebhookDir = Join-Path $RootDir "suma-webhook"
$WebhookJs = Join-Path $WebhookDir "webhook.js"

Write-Host ""
Write-Host "================================" -ForegroundColor Cyan
Write-Host "Suma Webhook Task Scheduler Setup" -ForegroundColor Cyan
Write-Host "================================" -ForegroundColor Cyan
Write-Host ""

# Check webhook.js exists
if (!(Test-Path $WebhookJs)) {
    Write-Host "[ERROR] webhook.js not found at: $WebhookJs" -ForegroundColor Red
    exit 1
}

Write-Host "[INFO] Webhook file found: $WebhookJs" -ForegroundColor Green

# Check Node.js
$nodeCmd = Get-Command node -ErrorAction SilentlyContinue
if (!$nodeCmd) {
    Write-Host "[ERROR] Node.js is not installed or not in PATH" -ForegroundColor Red
    Write-Host "Please install Node.js from: https://nodejs.org/" -ForegroundColor Yellow
    exit 1
}

$nodeVersion = node -v
Write-Host "[INFO] Node.js version: $nodeVersion" -ForegroundColor Green

# Check npm and install dependencies
Write-Host "[INFO] Checking webhook dependencies..." -ForegroundColor Cyan
Push-Location $WebhookDir
try {
    if (Test-Path "package.json") {
        $packageLock = Test-Path "package-lock.json"
        $nodeModules = Test-Path "node_modules"
        
        if (!$nodeModules -or !$packageLock) {
            Write-Host "[INFO] Installing npm dependencies..." -ForegroundColor Yellow
            npm install --production
            if ($LASTEXITCODE -ne 0) {
                Write-Host "[ERROR] Failed to install npm dependencies" -ForegroundColor Red
                exit 1
            }
            Write-Host "[INFO] Dependencies installed successfully" -ForegroundColor Green
        } else {
            Write-Host "[INFO] Dependencies already installed" -ForegroundColor Green
        }
    }
} finally {
    Pop-Location
}

# Task Scheduler setup
$TaskName = "SumaWebhookService"
$TaskDescription = "Suma Webhook Service - Runs webhook.js on system startup"

if ($Uninstall) {
    Write-Host ""
    Write-Host "[INFO] Uninstalling task scheduler..." -ForegroundColor Yellow
    
    # Check if task exists
    $existingTask = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    
    if ($existingTask) {
        # Stop if running
        $runningTask = Get-ScheduledTask -TaskName $TaskName | Where-Object {$_.State -eq "Running"}
        if ($runningTask) {
            Write-Host "[INFO] Stopping running task..." -ForegroundColor Yellow
            Stop-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 2
        }
        
        # Unregister task
        Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
        Write-Host "[SUCCESS] Task scheduler removed successfully" -ForegroundColor Green
        
        # Check if process is still running on port 5000
        $portUsed = Get-NetTCPConnection -LocalPort 5000 -State Listen -ErrorAction SilentlyContinue
        if ($portUsed) {
            Write-Host "[INFO] Stopping webhook process on port 5000..." -ForegroundColor Yellow
            Stop-Process -Id $portUsed.OwningProcess -Force -ErrorAction SilentlyContinue
            Write-Host "[SUCCESS] Webhook process stopped" -ForegroundColor Green
        }
    } else {
        Write-Host "[INFO] Task scheduler not found - nothing to uninstall" -ForegroundColor Yellow
    }
    
    Write-Host ""
    exit 0
}

# Install/Update Task Scheduler
Write-Host ""
Write-Host "[INFO] Setting up task scheduler..." -ForegroundColor Cyan

# Check if webhook is already running
$portUsed = Get-NetTCPConnection -LocalPort 5000 -State Listen -ErrorAction SilentlyContinue
if ($portUsed) {
    Write-Host "[INFO] Webhook already running on port 5000 (PID: $($portUsed.OwningProcess))" -ForegroundColor Yellow
    Write-Host "[INFO] Stopping existing process..." -ForegroundColor Yellow
    Stop-Process -Id $portUsed.OwningProcess -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
    Write-Host "[INFO] Process stopped" -ForegroundColor Green
}

# Remove existing task if exists
$existingTask = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
if ($existingTask) {
    Write-Host "[INFO] Removing existing task..." -ForegroundColor Yellow
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
}

# Create new scheduled task
Write-Host "[INFO] Creating scheduled task..." -ForegroundColor Cyan

$Action = New-ScheduledTaskAction -Execute $nodeCmd.Source `
    -Argument "`"$WebhookJs`"" `
    -WorkingDirectory $WebhookDir

$Trigger = New-ScheduledTaskTrigger -AtStartup

$Settings = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -StartWhenAvailable `
    -RestartCount 3 `
    -RestartInterval (New-TimeSpan -Minutes 1) `
    -ExecutionTimeLimit (New-TimeSpan -Hours 0)

$Principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest

Register-ScheduledTask -TaskName $TaskName `
    -Action $Action `
    -Trigger $Trigger `
    -Settings $Settings `
    -Principal $Principal `
    -Description $TaskDescription | Out-Null

Write-Host "[SUCCESS] Task scheduler created successfully" -ForegroundColor Green

# Start the task now
Write-Host "[INFO] Starting webhook service..." -ForegroundColor Cyan
Start-ScheduledTask -TaskName $TaskName

# Wait a bit and check if it's running
Start-Sleep -Seconds 3

$taskStatus = Get-ScheduledTask -TaskName $TaskName
Write-Host "[INFO] Task Status: $($taskStatus.State)" -ForegroundColor Cyan

# Check if webhook is listening on port 5000
$portCheck = Get-NetTCPConnection -LocalPort 5000 -State Listen -ErrorAction SilentlyContinue
if ($portCheck) {
    Write-Host "[SUCCESS] Webhook is running on port 5000 (PID: $($portCheck.OwningProcess))" -ForegroundColor Green
} else {
    Write-Host "[WARNING] Webhook may not be running yet - check Task Scheduler for details" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "================================" -ForegroundColor Green
Write-Host "Setup Complete!" -ForegroundColor Green
Write-Host "================================" -ForegroundColor Green
Write-Host ""
Write-Host "Task Name: $TaskName" -ForegroundColor White
Write-Host "Webhook will start automatically on system boot" -ForegroundColor White
Write-Host ""
Write-Host "Commands:" -ForegroundColor Cyan
Write-Host "  View task:      Get-ScheduledTask -TaskName '$TaskName'" -ForegroundColor Gray
Write-Host "  Start task:     Start-ScheduledTask -TaskName '$TaskName'" -ForegroundColor Gray
Write-Host "  Stop task:      Stop-ScheduledTask -TaskName '$TaskName'" -ForegroundColor Gray
Write-Host "  Check webhook:  Get-NetTCPConnection -LocalPort 5000" -ForegroundColor Gray
Write-Host "  Uninstall:      .\setup-webhook-scheduler.ps1 -Uninstall" -ForegroundColor Gray
Write-Host ""
