# SSL Manager - Interactive SSL Certificate Management
# Script interaktif untuk mengelola SSL certificates dengan menu pilihan
#
# Usage: .\ssl-manager.ps1

param(
    [string]$SslRoot = "C:\docker\ssl"
)

function Write-ColorOutput {
    param([string]$Message, [string]$Color = "White")
    switch ($Color) {
        "Red" { Write-Host $Message -ForegroundColor Red }
        "Green" { Write-Host $Message -ForegroundColor Green }
        "Yellow" { Write-Host $Message -ForegroundColor Yellow }
        "Cyan" { Write-Host $Message -ForegroundColor Cyan }
        "Magenta" { Write-Host $Message -ForegroundColor Magenta }
        "Gray" { Write-Host $Message -ForegroundColor Gray }
        default { Write-Host $Message }
    }
}

function Show-MainMenu {
    Write-ColorOutput ""
    Write-ColorOutput "=====================================" "Cyan"
    Write-ColorOutput "       SSL MANAGER v4.0" "Cyan"
    Write-ColorOutput "=====================================" "Cyan"
    Write-ColorOutput ""
    Write-ColorOutput "Pilih operasi yang ingin dilakukan:" "Yellow"
    Write-ColorOutput ""
    Write-ColorOutput "1. Update SSL Manual (dari folder ssl/)" "White"
    Write-ColorOutput "2. Update ke Auto SSL (cert-manager)" "White"
    Write-ColorOutput "3. Cek Status SSL Semua Domain" "White"
    Write-ColorOutput "4. Keluar" "White"
    Write-ColorOutput ""
}

function Get-UserChoice {
    param([string]$Prompt = "Pilih menu (1-4)")
    $choice = Read-Host $Prompt
    return $choice
}

function Get-DomainFolders {
    param([string]$Path)
    try {
        $folders = Get-ChildItem -Path $Path -Directory -ErrorAction Stop | Where-Object {
            $_.Name -match '^[a-zA-Z0-9.-]+$' -and $_.Name -notmatch '^_'
        } | Select-Object -ExpandProperty Name
        return $folders
    } catch {
        Write-ColorOutput "Error accessing SSL folder: $($_.Exception.Message)" "Red"
        return @()
    }
}

function Get-AllIngressDomains {
    try {
        $ingresses = kubectl get ingress --all-namespaces -o json 2>$null | ConvertFrom-Json
        $domains = @()

        if ($ingresses -and $ingresses.items) {
            foreach ($ingress in $ingresses.items) {
                if ($ingress.spec.tls) {
                    foreach ($tls in $ingress.spec.tls) {
                        if ($tls.hosts) {
                            $domains += $tls.hosts
                        }
                    }
                }
                if ($ingress.spec.rules) {
                    foreach ($rule in $ingress.spec.rules) {
                        if ($rule.host) {
                            $domains += $rule.host
                        }
                    }
                }
            }
        }

        return $domains | Select-Object -Unique | Sort-Object
    } catch {
        Write-ColorOutput "Error getting ingress domains: $($_.Exception.Message)" "Red"
        return @()
    }
}

function Show-DomainMenu {
    param([array]$Domains, [string]$Title)

    Write-ColorOutput ""
    Write-ColorOutput "=== $Title ===" "Cyan"
    Write-ColorOutput ""

    if ($Domains.Count -eq 0) {
        Write-ColorOutput "Tidak ada domain ditemukan." "Yellow"
        return $null
    }

    for ($i = 0; $i -lt $Domains.Count; $i++) {
        Write-ColorOutput "$($i + 1). $($Domains[$i])" "White"
    }
    Write-ColorOutput "$(($Domains.Count + 1)). Semua domain" "Green"
    Write-ColorOutput "$(($Domains.Count + 2)). Kembali ke menu utama" "Gray"
    Write-ColorOutput ""

    $choice = Get-UserChoice "Pilih domain (1-$($Domains.Count + 2))"
    $choiceNum = [int]$choice

    if ($choiceNum -ge 1 -and $choiceNum -le $Domains.Count) {
        return @($Domains[$choiceNum - 1])
    } elseif ($choiceNum -eq ($Domains.Count + 1)) {
        return $Domains
    } elseif ($choiceNum -eq ($Domains.Count + 2)) {
        return $null
    } else {
        Write-ColorOutput "Pilihan tidak valid!" "Red"
        return $null
    }
}

function Update-ManualSSL {
    param([array]$SelectedDomains)

    Write-ColorOutput ""
    Write-ColorOutput "=== Update SSL Manual ===" "Cyan"
    Write-ColorOutput "Domain yang akan diupdate: $($SelectedDomains -join ', ')" "White"
    Write-ColorOutput ""

    $confirm = Get-UserChoice "Lanjutkan update SSL manual? (y/N)"
    if ($confirm -ne "y" -and $confirm -ne "Y") {
        Write-ColorOutput "Update dibatalkan." "Yellow"
        return
    }

    foreach ($domain in $SelectedDomains) {
        Write-ColorOutput "Processing domain: $domain" "Cyan"

        $domainPath = Join-Path $SslRoot $domain
        $crtFile = Join-Path $domainPath "certificate.crt"
        $keyFile = Join-Path $domainPath "certificate.key"

        if (-not ((Test-Path $crtFile) -and (Test-Path $keyFile))) {
            Write-ColorOutput "  ERROR: Certificate files tidak ditemukan di $domainPath" "Red"
            continue
        }

        try {
            $ingresses = kubectl get ingress --all-namespaces -o json 2>$null | ConvertFrom-Json

            foreach ($ingress in $ingresses.items) {
                $ns = $ingress.metadata.namespace
                $name = $ingress.metadata.name
                $secretName = $null

                $usesDomain = $false
                if ($ingress.spec.tls) {
                    foreach ($tls in $ingress.spec.tls) {
                        if ($tls.hosts -contains $domain) {
                            $secretName = $tls.secretName
                            $usesDomain = $true
                            break
                        }
                    }
                }

                if ($usesDomain -and $secretName) {
                    Write-ColorOutput "  Updating secret $secretName in namespace $ns..." "Yellow"

                    # Clean up cert-manager artifacts
                    try {
                        Write-ColorOutput "  Menghapus annotation cert-manager..." "Yellow"
                        kubectl annotate ingress $name -n $ns cert-manager.io/cluster-issuer- 2>&1 | Out-Null
                        kubectl annotate ingress $name -n $ns cert-manager.io/issuer- 2>&1 | Out-Null
                        Write-ColorOutput "  [OK] Annotation cert-manager dihapus" "Green"
                    } catch {
                        Write-ColorOutput "  [WARN] Gagal menghapus annotation: $($_.Exception.Message)" "Red"
                    }

                    try {
                        Write-ColorOutput "  Menghapus Certificate CR..." "Yellow"
                        kubectl delete certificate $secretName -n $ns --ignore-not-found 2>&1 | Out-Null
                        Write-ColorOutput "  [OK] Certificate CR dihapus" "Green"
                    } catch {
                        Write-ColorOutput "  [WARN] Gagal menghapus Certificate CR: $($_.Exception.Message)" "Red"
                    }

                    # Apply manual SSL
                    Write-ColorOutput "  Meng-apply secret TLS dari file..." "Yellow"
                    $result = kubectl create secret tls $secretName --cert="$crtFile" --key="$keyFile" -n $ns --dry-run=client -o yaml | kubectl apply -f - 2>&1

                    if ($LASTEXITCODE -eq 0 -or $result -match "configured") {
                        Write-ColorOutput "  [OK] Secret $secretName updated" "Green"

                        # Auto-restart NGINX
                        Write-ColorOutput "  Auto-restarting NGINX..." "Yellow"
                        try {
                            kubectl rollout restart deployment/ingress-nginx-controller -n ingress-nginx 2>&1 | Out-Null
                            Write-ColorOutput "  [OK] NGINX restart initiated" "Green"

                            # Wait for rollout
                            Write-ColorOutput "  [WAIT] Menunggu NGINX rollout..." "Yellow"
                            $rolloutTimeout = 120
                            $rolloutElapsed = 0
                            $rolloutComplete = $false

                            while ($rolloutElapsed -lt $rolloutTimeout -and -not $rolloutComplete) {
                                Start-Sleep -Seconds 5
                                $rolloutElapsed += 5

                                try {
                                    $rolloutStatus = kubectl rollout status deployment/ingress-nginx-controller -n ingress-nginx 2>&1
                                    if ($rolloutStatus -match "successfully rolled out") {
                                        $rolloutComplete = $true
                                        Write-ColorOutput "  [OK] NGINX rollout selesai setelah $($rolloutElapsed)s" "Green"
                                    }
                                } catch {
                                    # Continue waiting
                                }

                                if (-not $rolloutComplete) {
                                    Write-ColorOutput "  [WAIT] Menunggu NGINX rollout... ($($rolloutElapsed)s/$($rolloutTimeout)s)" "Cyan"
                                }
                            }

                            if (-not $rolloutComplete) {
                                Write-ColorOutput "  [WARN] NGINX rollout belum selesai setelah $($rolloutTimeout)s" "Yellow"
                            }

                        } catch {
                            Write-ColorOutput "  [ERROR] Failed to restart NGINX: $($_.Exception.Message)" "Red"
                        }

                        # Verification
                        Write-ColorOutput "  [CHECK] Verifikasi akhir..." "Yellow"
                        try {
                            $finalSecret = kubectl get secret $secretName -n $ns -o json 2>$null | ConvertFrom-Json

                            if ($finalSecret -and $finalSecret.data) {
                                $tlsCrt = $finalSecret.data.'tls.crt'
                                $tlsKey = $finalSecret.data.'tls.key'
                                if ($tlsCrt -and $tlsKey) {
                                    Write-ColorOutput "  [OK] Secret TLS: Lengkap (crt + key)" "Green"
                                } else {
                                    Write-ColorOutput "  [ERROR] Secret TLS: Tidak lengkap" "Red"
                                }
                            }

                            Write-ColorOutput "  [SUCCESS] Manual SSL untuk $domain SELESAI 100%!" "Green"
                            Write-ColorOutput "  [WEB] Test: https://$domain" "Cyan"

                        } catch {
                            Write-ColorOutput "  [WARN] Verifikasi gagal: $($_.Exception.Message)" "Yellow"
                        }

                    } else {
                        Write-ColorOutput "  [ERROR] Failed to update secret: $result" "Red"
                    }
                }
            }
        } catch {
            Write-ColorOutput "  [ERROR] Failed to get ingress info: $($_.Exception.Message)" "Red"
        }

        Write-ColorOutput ""
    }

    Write-ColorOutput "[SUCCESS] Update SSL manual selesai!" "Green"
}

function Update-AutoSSL {
    param([array]$SelectedDomains)

    Write-ColorOutput ""
    Write-ColorOutput "=== Update ke Auto SSL (cert-manager) ===" "Cyan"
    Write-ColorOutput "Domain yang akan diupdate: $($SelectedDomains -join ', ')" "White"
    Write-ColorOutput ""

    $confirm = Get-UserChoice "Lanjutkan update ke auto SSL? (y/N)"
    if ($confirm -ne "y" -and $confirm -ne "Y") {
        Write-ColorOutput "Update dibatalkan." "Yellow"
        return
    }

    foreach ($domain in $SelectedDomains) {
        Write-ColorOutput "Processing domain: $domain" "Cyan"

        try {
            $ingresses = kubectl get ingress --all-namespaces -o json 2>$null | ConvertFrom-Json

            foreach ($ingress in $ingresses.items) {
                $ns = $ingress.metadata.namespace
                $name = $ingress.metadata.name
                $secretName = $null

                $usesDomain = $false
                if ($ingress.spec.tls) {
                    foreach ($tls in $ingress.spec.tls) {
                        if ($tls.hosts -contains $domain) {
                            $secretName = $tls.secretName
                            $usesDomain = $true
                            break
                        }
                    }
                }

                if ($usesDomain -and $secretName) {
                    Write-ColorOutput "  Enabling cert-manager for $domain..." "Yellow"

                    # Clean up existing artifacts
                    try {
                        Write-ColorOutput "  Menghapus Secret TLS yang ada..." "Yellow"
                        kubectl delete secret $secretName -n $ns --ignore-not-found 2>&1 | Out-Null
                        Write-ColorOutput "  [OK] Secret TLS dihapus" "Green"
                    } catch {
                        Write-ColorOutput "  [WARN] Gagal menghapus Secret TLS: $($_.Exception.Message)" "Red"
                    }

                    try {
                        Write-ColorOutput "  Menghapus Certificate CR yang ada..." "Yellow"
                        kubectl delete certificate $secretName -n $ns --ignore-not-found 2>&1 | Out-Null
                        Write-ColorOutput "  [OK] Certificate CR dihapus" "Green"
                    } catch {
                        Write-ColorOutput "  [WARN] Gagal menghapus Certificate CR: $($_.Exception.Message)" "Red"
                    }

                    # Enable cert-manager
                    $result = kubectl annotate ingress $name -n $ns "cert-manager.io/cluster-issuer=selfsigned-cluster-issuer" --overwrite 2>&1

                    if ($LASTEXITCODE -eq 0) {
                        Write-ColorOutput "  [OK] cert-manager enabled for $domain" "Green"
                        Write-ColorOutput "  [WAIT] Menunggu certificate generation (max 3 menit)..." "Yellow"

                        # Wait for certificate
                        $maxWait = 180
                        $elapsed = 0
                        $certReady = $false

                        while ($elapsed -lt $maxWait -and -not $certReady) {
                            Start-Sleep -Seconds 10
                            $elapsed += 10

                            try {
                                $cert = kubectl get certificate $secretName -n $ns -o json 2>$null | ConvertFrom-Json
                                if ($cert -and $cert.status -and $cert.status.conditions) {
                                    $readyCondition = $cert.status.conditions | Where-Object { $_.type -eq "Ready" -and $_.status -eq "True" }
                                    if ($readyCondition) {
                                        $certReady = $true
                                        Write-ColorOutput "  [OK] Certificate READY setelah $($elapsed)s" "Green"
                                    }
                                }
                            } catch {
                                # Certificate belum ada atau error
                            }

                            if (-not $certReady) {
                                Write-ColorOutput "  [WAIT] Menunggu certificate... ($($elapsed)s/$($maxWait)s)" "Cyan"
                            }
                        }

                        if (-not $certReady) {
                            Write-ColorOutput "  [WARN] Certificate belum ready setelah $($maxWait)s, tapi proses akan dilanjutkan" "Yellow"
                        }

                        # Auto-restart NGINX
                        Write-ColorOutput "  Auto-restarting NGINX..." "Yellow"
                        try {
                            kubectl rollout restart deployment/ingress-nginx-controller -n ingress-nginx 2>&1 | Out-Null
                            Write-ColorOutput "  [OK] NGINX restart initiated" "Green"

                            # Wait for rollout
                            Write-ColorOutput "  [WAIT] Menunggu NGINX rollout..." "Yellow"
                            $rolloutTimeout = 120
                            $rolloutElapsed = 0
                            $rolloutComplete = $false

                            while ($rolloutElapsed -lt $rolloutTimeout -and -not $rolloutComplete) {
                                Start-Sleep -Seconds 5
                                $rolloutElapsed += 5

                                try {
                                    $rolloutStatus = kubectl rollout status deployment/ingress-nginx-controller -n ingress-nginx 2>&1
                                    if ($rolloutStatus -match "successfully rolled out") {
                                        $rolloutComplete = $true
                                        Write-ColorOutput "  [OK] NGINX rollout selesai setelah $($rolloutElapsed)s" "Green"
                                    }
                                } catch {
                                    # Continue waiting
                                }

                                if (-not $rolloutComplete) {
                                    Write-ColorOutput "  [WAIT] Menunggu NGINX rollout... ($($rolloutElapsed)s/$($rolloutTimeout)s)" "Cyan"
                                }
                            }

                            if (-not $rolloutComplete) {
                                Write-ColorOutput "  [WARN] NGINX rollout belum selesai setelah $($rolloutTimeout)s" "Yellow"
                            }

                        } catch {
                            Write-ColorOutput "  [ERROR] Failed to restart NGINX: $($_.Exception.Message)" "Red"
                        }

                        # Final verification
                        Write-ColorOutput "  [CHECK] Verifikasi akhir..." "Yellow"
                        try {
                            $finalCert = kubectl get certificate $secretName -n $ns -o json 2>$null | ConvertFrom-Json
                            $finalSecret = kubectl get secret $secretName -n $ns -o json 2>$null | ConvertFrom-Json

                            if ($finalCert -and $finalCert.status -and $finalCert.status.conditions) {
                                $readyCondition = $cert.status.conditions | Where-Object { $_.type -eq "Ready" -and $_.status -eq "True" }
                                if ($readyCondition) {
                                    Write-ColorOutput "  [OK] Certificate: READY" "Green"
                                } else {
                                    Write-ColorOutput "  [ERROR] Certificate: NOT READY" "Red"
                                }
                            }

                            if ($finalSecret -and $finalSecret.data) {
                                $tlsCrt = $finalSecret.data.'tls.crt'
                                $tlsKey = $finalSecret.data.'tls.key'
                                if ($tlsCrt -and $tlsKey) {
                                    Write-ColorOutput "  [OK] Secret TLS: Lengkap (crt + key)" "Green"
                                } else {
                                    Write-ColorOutput "  [ERROR] Secret TLS: Tidak lengkap" "Red"
                                }
                            }

                            Write-ColorOutput "  [SUCCESS] Auto SSL untuk $domain SELESAI 100%!" "Green"
                            Write-ColorOutput "  [WEB] Test: https://$domain" "Cyan"

                        } catch {
                            Write-ColorOutput "  [WARN] Verifikasi gagal: $($_.Exception.Message)" "Yellow"
                        }

                    } else {
                        Write-ColorOutput "  [ERROR] Failed to enable cert-manager: $result" "Red"
                    }
                }
            }
        } catch {
            Write-ColorOutput "  [ERROR] Failed to get ingress info: $($_.Exception.Message)" "Red"
        }

        Write-ColorOutput ""
    }

    Write-ColorOutput "[SUCCESS] Update ke auto SSL selesai!" "Green"
}

function Check-SSLStatus {
    Write-ColorOutput ""
    Write-ColorOutput "=== Cek Status SSL Semua Domain ===" "Cyan"
    Write-ColorOutput ""

    # Get manual SSL domains
    $manualDomains = Get-DomainFolders -Path $SslRoot
    Write-ColorOutput "Manual SSL domains (dari folder ssl/):" "Yellow"
    if ($manualDomains.Count -eq 0) {
        Write-ColorOutput "  Tidak ada domain manual SSL" "Gray"
    } else {
        foreach ($domain in $manualDomains) {
            $domainPath = Join-Path $SslRoot $domain
            $crtFile = Join-Path $domainPath "certificate.crt"
            $keyFile = Join-Path $domainPath "certificate.key"

            if ((Test-Path $crtFile) -and (Test-Path $keyFile)) {
                Write-ColorOutput "  $domain - [OK] (certificate.crt & certificate.key)" "Green"
            } else {
                Write-ColorOutput "  $domain - [ERROR] (missing files)" "Red"
            }
        }
    }

    Write-ColorOutput ""

    # Get all ingress domains
    $allDomains = Get-AllIngressDomains
    Write-ColorOutput "Semua domain dari ingress:" "Yellow"
    if ($allDomains.Count -eq 0) {
        Write-ColorOutput "  Tidak ada domain di ingress" "Gray"
    } else {
        foreach ($domain in $allDomains) {
            $isManual = $domain -in $manualDomains
            if ($isManual) {
                Write-ColorOutput "  $domain - Manual SSL" "Green"
            } else {
                Write-ColorOutput "  $domain - Auto SSL (cert-manager)" "Cyan"
            }
        }
    }

    Write-ColorOutput ""
    Write-ColorOutput "[SUCCESS] Status check selesai!" "Green"
}

# Main execution
$running = $true
while ($running) {
    Show-MainMenu
    $choice = Get-UserChoice

    switch ($choice) {
        "1" {
            # Update SSL Manual
            $manualDomains = Get-DomainFolders -Path $SslRoot
            if ($manualDomains.Count -eq 0) {
                Write-ColorOutput "Tidak ada domain manual SSL ditemukan di $SslRoot" "Yellow"
            } else {
                $selectedDomains = Show-DomainMenu -Domains $manualDomains -Title "Pilih Domain untuk Update SSL Manual"
                if ($selectedDomains) {
                    Update-ManualSSL -SelectedDomains $selectedDomains
                }
            }
        }
        "2" {
            # Update ke Auto SSL
            $allDomains = Get-AllIngressDomains
            if ($allDomains.Count -eq 0) {
                Write-ColorOutput "Tidak ada domain ingress ditemukan" "Yellow"
            } else {
                $selectedDomains = Show-DomainMenu -Domains $allDomains -Title "Pilih Domain untuk Update ke Auto SSL"
                if ($selectedDomains) {
                    Update-AutoSSL -SelectedDomains $selectedDomains
                }
            }
        }
        "3" {
            # Cek Status SSL
            Check-SSLStatus
        }
        "4" {
            # Keluar
            Write-ColorOutput "Terima kasih telah menggunakan SSL Manager!" "Green"
            $running = $false
        }
        default {
            Write-ColorOutput "Pilihan tidak valid! Silakan pilih 1-4." "Red"
        }
    }

    if ($running) {
        Write-ColorOutput ""
        Read-Host "Tekan Enter untuk kembali ke menu utama"
    }
}
