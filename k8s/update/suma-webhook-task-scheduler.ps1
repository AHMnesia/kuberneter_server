# Check if running as administrator
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "Task scheduler gagal dijalankan, script ini harus dijalankan dengan hak Administrator." -ForegroundColor Red
    exit 1
}

$root = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent   # c:\docker

# Pastikan Node.js tersedia di host. Jika tidak ditemukan, coba install otomatis
function Ensure-Node {
    Write-Host "Memeriksa ketersediaan Node.js..." -ForegroundColor Gray

    $hasNode = Get-Command node -ErrorAction SilentlyContinue
    $hasNpm = Get-Command npm -ErrorAction SilentlyContinue

    if (-not $hasNode) {
        Write-Host "Node.js tidak ditemukan." -ForegroundColor Yellow
        if ($IsLinux) {
            Write-Host "Mencoba menginstall Node.js di Linux (mendeteksi package manager)..." -ForegroundColor Cyan
            # Detect package manager
            $pkg = if (Get-Command apt-get -ErrorAction SilentlyContinue) { 'apt' } elseif (Get-Command dnf -ErrorAction SilentlyContinue) { 'dnf' } elseif (Get-Command yum -ErrorAction SilentlyContinue) { 'yum' } elseif (Get-Command apk -ErrorAction SilentlyContinue) { 'apk' } elseif (Get-Command pacman -ErrorAction SilentlyContinue) { 'pacman' } else { $null }
            if ($pkg -eq 'apt') {
                $cmd = 'set -e; curl -fsSL https://deb.nodesource.com/setup_20.x | bash -; apt-get install -y nodejs build-essential'
            } elseif ($pkg -eq 'dnf' -or $pkg -eq 'yum') {
                $cmd = 'set -e; curl -fsSL https://rpm.nodesource.com/setup_20.x | bash -; if command -v dnf >/dev/null 2>&1; then dnf install -y nodejs; else yum install -y nodejs; fi'
            } elseif ($pkg -eq 'apk') {
                $cmd = 'set -e; apk add --no-cache nodejs npm build-base'
            } elseif ($pkg -eq 'pacman') {
                $cmd = 'set -e; pacman -Sy --noconfirm nodejs npm'
            } else {
                Write-Host "Tidak menemukan package manager yang dikenali di Linux. Silakan install Node.js manual." -ForegroundColor Red
                $cmd = $null
            }
            if ($cmd) {
                try {
                    Write-Host "Menjalankan instalasi Node dengan sudo: $pkg" -ForegroundColor Cyan
                    Start-Process -FilePath 'bash' -ArgumentList '-lc', $cmd -NoNewWindow -Wait -ErrorAction Stop
                } catch {
                    Write-Host "Gagal menjalankan instalasi Node otomatis: $_" -ForegroundColor Red
                }
            }
        } else {
            # Coba install via winget atau choco jika tersedia (Windows)
            if (Get-Command winget -ErrorAction SilentlyContinue) {
                Write-Host "Mencoba menginstall Node.js via winget..." -ForegroundColor Cyan
                try { winget install --id OpenJS.NodeJS.LTS -e --accept-package-agreements --accept-source-agreements -h } catch { Write-Host "Install Node via winget gagal: $_" -ForegroundColor Red }
            } elseif (Get-Command choco -ErrorAction SilentlyContinue) {
                Write-Host "Mencoba menginstall Node.js via choco..." -ForegroundColor Cyan
                try { choco install nodejs-lts -y } catch { Write-Host "Install Node via choco gagal: $_" -ForegroundColor Red }
            } else {
                Write-Host "Tidak ada package manager (winget/choco) untuk menginstall Node otomatis. Silakan install Node.js manual." -ForegroundColor Red
            }
        }
        # refresh command lookup
        Start-Sleep -Seconds 2
        $hasNode = Get-Command node -ErrorAction SilentlyContinue
        $hasNpm = Get-Command npm -ErrorAction SilentlyContinue
    } else {
        Write-Host "Node.js ditemukan: $(node -v)" -ForegroundColor Green
    }

    if (-not $hasNpm -and $hasNode) {
        # npm biasanya hadir bersama Node; beri peringatan jika hilang
        Write-Host "npm tidak ditemukan meskipun Node ada. Silakan periksa instalasi Node." -ForegroundColor Yellow
    }
}

Ensure-Node
    

# Menjalankan server webhook
$webhookJs = Join-Path $root 'suma-webhook\webhook.js'
Write-Host "Mencari file webhook.js di: $webhookJs" -ForegroundColor Gray
if (Test-Path $webhookJs) {
    $portUsed = Get-NetTCPConnection -LocalPort 5000 -State Listen -ErrorAction SilentlyContinue
    if ($portUsed) {
        Write-Host "webhook.js sudah berjalan di port 5000. Menghentikan proses lama dan menjalankan ulang..." -ForegroundColor Yellow
        try {
            Stop-Process -Id $portUsed.OwningProcess -Force -ErrorAction Stop
            Write-Host "Proses lama berhasil dihentikan." -ForegroundColor Green
            Start-Sleep -Seconds 2  # Tunggu sebentar agar port bebas
        } catch {
            Write-Host "Gagal menghentikan proses lama: $_" -ForegroundColor Red
        }
    }
    $os = $env:OS
    $startedVia = $null
    if ($os -like '*Windows*') {
        Write-Host "Deteksi OS: Windows." -ForegroundColor Cyan
        $pm2cmd = Get-Command pm2 -ErrorAction SilentlyContinue
        $pm2InstallAttempted = $false
        if (-not $pm2cmd) {
            $npmCmd = Get-Command npm -ErrorAction SilentlyContinue
            if ($npmCmd) {
                Write-Host "pm2 tidak ditemukan. Mencoba memasang pm2 global via npm..." -ForegroundColor Cyan
                try {
                    $pm2InstallAttempted = $true
                    Start-Process -FilePath $npmCmd.Source -ArgumentList 'install','-g','pm2' -NoNewWindow -Wait -ErrorAction Stop
                    Write-Host "Instalasi pm2 selesai." -ForegroundColor Green
                } catch {
                    Write-Host "Gagal memasang pm2 otomatis: $_" -ForegroundColor Yellow
                }
                $pm2cmd = Get-Command pm2 -ErrorAction SilentlyContinue
            } else {
                Write-Host "npm tidak tersedia sehingga pm2 tidak dapat dipasang otomatis." -ForegroundColor Yellow
            }
        }

        if ($pm2cmd) {
            function Invoke-Pm2Windows {
                param(
                    [string[]]$Arguments,
                    [switch]$IgnoreError,
                    [string]$StepDescription = '',
                    [switch]$Silent
                )

                if ($StepDescription) {
                    Write-Host "  → Menjalankan pm2 $StepDescription..." -ForegroundColor DarkCyan
                }

                $pm2Path = $pm2cmd.Source
                if ($pm2Path.EndsWith('.ps1')) {
                    $pm2CmdShim = Join-Path (Split-Path $pm2Path -Parent) 'pm2.cmd'
                    if (Test-Path $pm2CmdShim) {
                        $pm2Path = $pm2CmdShim
                    }
                }

                $quoteArg = {
                    param($value)
                    if (-not $value) { '""' }
                    elseif ($value -match '\s') { '"{0}"' -f $value }
                    else { $value }
                }

                $cmdString = '"{0}" {1}' -f $pm2Path, (($Arguments | ForEach-Object { & $quoteArg $_ }) -join ' ')
                if ($Silent) { $cmdString = "$cmdString >nul 2>nul" }

                $filePath = 'cmd.exe'
                $argList = @('/c', $cmdString)

                $process = Start-Process -FilePath $filePath -ArgumentList $argList -NoNewWindow -PassThru -Wait

                if (-not $process) {
                    if ($IgnoreError) { return }
                    throw "Tidak dapat menjalankan perintah pm2 ($($Arguments -join ' '))"
                }

                if ($process.ExitCode -ne 0) {
                    if ($IgnoreError) {
                        $reason = if ($StepDescription) { "$StepDescription (exit $($process.ExitCode))" } else { "perintah ($($Arguments -join ' '))" }
                        Write-Host "    pm2 $reason diabaikan." -ForegroundColor DarkYellow
                    } else {
                        throw "Perintah pm2 gagal (exit $($process.ExitCode)): $($Arguments -join ' ')"
                    }
                } elseif ($StepDescription) {
                    Write-Host "    pm2 $StepDescription selesai." -ForegroundColor DarkGray
                }
            }

            Write-Host "pm2 ditemukan. Menggunakan pm2 untuk menjalankan webhook.js..." -ForegroundColor Green
            try {
                Invoke-Pm2Windows @('delete', 'suma-webhook') -IgnoreError -StepDescription 'delete suma-webhook (jika ada)' -Silent
                Invoke-Pm2Windows @('start', $webhookJs, '--name', 'suma-webhook', '--restart-delay', '1000', '--max-memory-restart', '200M') -StepDescription 'start webhook'
                Invoke-Pm2Windows @('install', 'pm2-windows-startup') -IgnoreError -StepDescription 'install pm2-windows-startup'
                Invoke-Pm2Windows @('save') -StepDescription 'save proses'
                Write-Host "pm2 berhasil dikonfigurasi untuk menjalankan webhook.js secara otomatis." -ForegroundColor Green
                $startedVia = 'pm2-windows'
            } catch {
                Write-Host "Gagal mengatur pm2 di Windows: $_" -ForegroundColor Yellow
            }
        }

        if (-not $startedVia) {
            $fallbackReason = if ($pm2cmd) { 'konfigurasi pm2 gagal' } elseif ($pm2InstallAttempted) { 'pm2 gagal dipasang' } else { 'pm2 tidak tersedia' }
            Write-Host "pm2 tidak digunakan (alasan: $fallbackReason). Menggunakan Task Scheduler sebagai cadangan." -ForegroundColor Cyan
            $nodeCmd = Get-Command node -ErrorAction Stop
            $actionArgs = '"' + $webhookJs + '"'
            Write-Host "Menjalankan webhook.js secara langsung dan menyiapkan Task Scheduler..." -ForegroundColor Cyan
            $quotedWebhook = '"' + $webhookJs + '"'
            Start-Process -NoNewWindow -FilePath $nodeCmd.Source -ArgumentList $quotedWebhook
            $taskName = "SumaWebhook"
            $existingTask = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
            if (-not $existingTask) {
                $action = New-ScheduledTaskAction -Execute $nodeCmd.Source -Argument $actionArgs -WorkingDirectory (Split-Path $webhookJs)
                $trigger = New-ScheduledTaskTrigger -AtStartup
                Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Description "Start webhook.js at server startup" -User "SYSTEM" -RunLevel Highest
                Write-Host "Task Scheduler untuk webhook.js berhasil dibuat." -ForegroundColor Green
            } else {
                Write-Host "Task Scheduler untuk webhook.js sudah ada." -ForegroundColor Yellow
            }
            $startedVia = 'task-scheduler'
        }
    } elseif ($IsLinux) {
        Write-Host "Deteksi OS: Linux. Mengecek dan membuat service untuk webhook.js..." -ForegroundColor Cyan
        # Jika pm2 tersedia gunakan pm2 untuk menjalankan service, jika tidak buat systemd unit
        $pm2cmd = Get-Command pm2 -ErrorAction SilentlyContinue
        if ($pm2cmd) {
            Write-Host "pm2 ditemukan di Linux. Menggunakan pm2 untuk menjalankan aplikasi..." -ForegroundColor Green
            try {
                Start-Process -FilePath $pm2cmd.Source -ArgumentList 'start', $webhookJs, '--name', 'suma-webhook', '--restart-delay', '1000', '--max-memory-restart', '200M' -NoNewWindow -Wait
                Start-Process -FilePath $pm2cmd.Source -ArgumentList 'save' -NoNewWindow -Wait
                # gunakan environment user info
                $runUser = if ($env:SUDO_USER) { $env:SUDO_USER } elseif ($env:USER) { $env:USER } else { 'root' }
                $homeDir = if ($env:HOME) { $env:HOME } else { "/home/$runUser" }
                Write-Host "Menjalankan pm2 startup untuk systemd (user=$runUser, home=$homeDir)" -ForegroundColor Cyan
                Start-Process -FilePath $pm2cmd.Source -ArgumentList 'startup', 'systemd', '-u', $runUser, '--hp', $homeDir -NoNewWindow -Wait
                $startedVia = 'pm2-linux'
            } catch {
                Write-Host "Gagal mengatur pm2 di Linux: $_" -ForegroundColor Yellow
            }
        } else {
            Write-Host "pm2 tidak ditemukan di Linux. Membuat systemd unit langsung..." -ForegroundColor Cyan
            $serviceFile = "/etc/systemd/system/suma-webhook.service"
            if (-not (Test-Path $serviceFile)) {
                $serviceContent = "[Unit]\nDescription=Suma Webhook Service\nAfter=network.target\n\n[Service]\nType=simple\nExecStart=/usr/bin/node $root/suma-webhook/webhook.js\nRestart=always\nUser=root\n\n[Install]\nWantedBy=multi-user.target"
                try {
                    Set-Content -Path $serviceFile -Value $serviceContent -Force
                    Write-Host "Systemd service file untuk webhook.js berhasil dibuat." -ForegroundColor Green
                    Start-Process -FilePath 'systemctl' -ArgumentList 'daemon-reload' -NoNewWindow -Wait
                    Start-Process -FilePath 'systemctl' -ArgumentList 'enable','suma-webhook' -NoNewWindow -Wait
                    Start-Process -FilePath 'systemctl' -ArgumentList 'start','suma-webhook' -NoNewWindow -Wait
                    $startedVia = 'systemd-new'
                } catch {
                    Write-Host "Gagal membuat systemd unit: $_" -ForegroundColor Red
                }
            } else {
                Write-Host "Systemd service untuk webhook.js sudah ada." -ForegroundColor Yellow
                $startedVia = 'systemd-existing'
            }
        }
    } else {
        Write-Host "OS tidak dikenali, schedule otomatis tidak dibuat." -ForegroundColor Yellow
    }

    if (-not $startedVia -and -not ($os -like '*Windows*')) {
        Write-Host "Menjalankan server webhook (webhook.js) langsung dengan node..." -ForegroundColor Cyan
        Start-Process -NoNewWindow -FilePath "node" -ArgumentList $webhookJs
    }
} else {
    Write-Host "File webhook.js tidak ditemukan di suma-webhook ($webhookJs)." -ForegroundColor Yellow
}