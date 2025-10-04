param(
    [string]$Namespace = '',
    [string]$K8sFolder = '..\\',
    [string]$OutputPath = '.\\ingress-yaml'
)

# Pastikan kubectl tersedia
if (!(Get-Command kubectl -ErrorAction SilentlyContinue)) {
    Write-Error 'kubectl tidak ditemukan. Pastikan kubectl terinstall dan dikonfigurasi.'
    exit 1
}

# Buat folder output jika belum ada
if (!(Test-Path $OutputPath)) {
    New-Item -ItemType Directory -Path $OutputPath | Out-Null
}

# Fungsi untuk mendapatkan daftar ingress (nama & namespace) dari sebuah file YAML
function Get-IngressEntries {
    param([string]$FilePath)

    $entries = @()
    try {
        $json = kubectl apply --dry-run=client -f $FilePath -o json 2>$null
        if ($LASTEXITCODE -ne 0 -or -not $json) { throw "Dry-run gagal" }

        $parsed = $json | ConvertFrom-Json
        $items = if ($parsed.kind -eq 'List' -and $parsed.items) { $parsed.items } else { @($parsed) }

        foreach ($item in $items) {
            if ($item.kind -eq 'Ingress' -and $item.metadata -and -not [string]::IsNullOrWhiteSpace($item.metadata.name)) {
                $ns = if ($item.metadata.namespace) { $item.metadata.namespace } else { 'default' }
                $name = $item.metadata.name.Trim()
                $entries += [PSCustomObject]@{
                    Key       = "$ns/$name"
                    Namespace = $ns
                    Name      = $name
                    File      = $FilePath
                }
            }
        }
    } catch {
        # Fallback sederhana jika dry-run gagal
        $content = Get-Content $FilePath -Raw
        if ($content -match 'kind:\s*Ingress') {
            $nameMatches = Select-String -InputObject $content -Pattern '(?m)^\s*name:\s*(\S+)' -AllMatches
            $nsMatch = Select-String -InputObject $content -Pattern '(?m)^\s*namespace:\s*(\S+)' | Select-Object -First 1
            $ns = if ($nsMatch) { $nsMatch.Matches[0].Groups[1].Value } else { 'default' }

            foreach ($match in $nameMatches.Matches) {
                $name = $match.Groups[1].Value
                if ([string]::IsNullOrWhiteSpace($name)) { continue }
                $entries += [PSCustomObject]@{
                    Key       = "$ns/$name"
                    Namespace = $ns
                    Name      = $name
                    File      = $FilePath
                }
            }
        }
    }

    return $entries
}

# Cari semua file ingress (ingress.yaml, ingress-*.yaml, dsb) di folder k8s
$ingressFiles = Get-ChildItem -Path $K8sFolder -Recurse -Include '*ingress*.yaml','*ingress*.yml' -File
$existingIngress = @{}
foreach ($file in $ingressFiles) {
    $entries = Get-IngressEntries -FilePath $file.FullName
    foreach ($entry in $entries) {
        if ($Namespace -and $entry.Namespace -ne $Namespace) {
            continue
        }
        if ($existingIngress.ContainsKey($entry.Key)) {
            Write-Host "Peringatan: ingress $($entry.Key) didefinisikan lebih dari satu file. Menggunakan $($entry.File)." -ForegroundColor Yellow
        }
        $existingIngress[$entry.Key] = $entry
    }
}

# Dapatkan daftar ingress dari cluster
$allNamespaces = if ($Namespace) { @($Namespace) } else { (kubectl get namespaces -o json | ConvertFrom-Json).items.metadata.name }
$clusterIngress = @{}
$toDelete = @()
foreach ($ns in $allNamespaces) {
    $ingresses = kubectl get ingress -n $ns -o json 2>$null | ConvertFrom-Json
    if ($ingresses.items) {
        foreach ($ingress in $ingresses.items) {
            $key = "$($ingress.metadata.namespace)/$($ingress.metadata.name)"
            $clusterIngress[$key] = $ingress
        }
    }
}

# Bandingkan
$toApply = @()
$deletedCount = 0
$total = $clusterIngress.Count
$current = 0
foreach ($key in $clusterIngress.Keys) {
    $current++
    Write-Progress -Activity 'Scanning ingress' -Status "$($key)" -PercentComplete (($current / $total) * 100)

    if ($existingIngress.ContainsKey($key)) {
        # Use kubectl diff for more accurate comparison
        $entry = $existingIngress[$key]
        kubectl diff -f $entry.File --namespace $entry.Namespace 2>$null
        $hasDifferences = $LASTEXITCODE -ne 0

        if ($hasDifferences) {
            $toApply += @{
                Key       = $key
                Namespace = $entry.Namespace
                Name      = $entry.Name
                File      = $entry.File
                Action    = 'update'
            }
        }
    } else {
        Write-Host "Ingress $key ada di cluster tapi tidak ada file YAML."
        $ingressObj = $clusterIngress[$key]
        if ($ingressObj) {
            $toDelete += @{
                Key       = $key
                Namespace = $ingressObj.metadata.namespace
                Name      = $ingressObj.metadata.name
            }
        }
    }
}
Write-Progress -Activity 'Scanning ingress' -Completed

# Cek file yang tidak ada di cluster, apply ke cluster
foreach ($key in $existingIngress.Keys) {
    if (!$clusterIngress.ContainsKey($key)) {
        Write-Host "File YAML untuk $key ada, tapi ingress tidak ditemukan di cluster."
        $entry = $existingIngress[$key]
        $toApply += @{
            Key       = $key
            Namespace = $entry.Namespace
            Name      = $entry.Name
            File      = $entry.File
            Action    = 'create'
        }
    }
}

if ($toDelete.Count -gt 0) {
    Write-Host "`nMenghapus $($toDelete.Count) ingress lama yang tidak lagi memiliki file YAML:" -ForegroundColor Yellow
    foreach ($item in $toDelete) {
        Write-Host "Menghapus $($item.Key)..."
        $deleteResult = kubectl delete ingress $item.Name -n $item.Namespace --wait=true --ignore-not-found 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Host "  ✓ $($item.Key) - berhasil dihapus" -ForegroundColor Green
            $deletedCount++
            $waitStart = Get-Date
            while ($true) {
                kubectl get ingress $item.Name -n $item.Namespace 1>$null 2>$null
                if ($LASTEXITCODE -ne 0) { break }
                if ((Get-Date) - $waitStart -gt [TimeSpan]::FromSeconds(30)) {
                    Write-Host "  ⚠ $($item.Key) masih terdeteksi setelah 30 detik, lanjut proses apply." -ForegroundColor Yellow
                    break
                }
                Start-Sleep -Seconds 2
            }
        } else {
            Write-Host "  ✗ $($item.Key) - gagal dihapus: $deleteResult" -ForegroundColor Red
        }
    }
}

$createdCount = 0
$updatedCount = 0
$unchangedCount = 0
$skippedCount = 0
$errorCount = 0

if ($toApply.Count -eq 0) {
    Write-Host 'Tidak ada perubahan atau ingress baru untuk diterapkan.'
} else {
    Write-Host "`nMemproses $($toApply.Count) ingress:"

    $applyGroups = @{}
    foreach ($item in $toApply) {
        $filePath = $item.File
        if (-not $applyGroups.ContainsKey($filePath)) {
            $applyGroups[$filePath] = New-Object System.Collections.ArrayList
        }
        [void]$applyGroups[$filePath].Add($item)
    }

    foreach ($group in $applyGroups.GetEnumerator()) {
        $filePath = $group.Key
        $entries = $group.Value
        $keysDisplay = ($entries | ForEach-Object { $_.Key }) -join ', '

        Write-Host "Memproses file $filePath untuk ingress: $keysDisplay"

        # Clean the YAML file from generated fields before applying
        $content = Get-Content -Path $filePath -Raw

        # Remove status block
        $cleanContent = $content -replace '(?ms)^status:.*?(?=^\S|\z)', ''

        # Remove kubectl.kubernetes.io/last-applied-configuration annotation
        $cleanContent = $cleanContent -replace '(?ms)k\s*kubectl\.kubernetes\.io/last-applied-configuration:.*?(?=^\S|\z)', ''

        # Remove generated metadata fields
        $cleanContent = $cleanContent -replace '(?m)^  creationTimestamp:.*$', ''
        $cleanContent = $cleanContent -replace '(?m)^  generation:.*$', ''
        $cleanContent = $cleanContent -replace '(?m)^  resourceVersion:.*$', ''
        $cleanContent = $cleanContent -replace '(?m)^  uid:.*$', ''

        # Remove empty lines
        $cleanContent = ($cleanContent -split "`n" | Where-Object { $_.Trim() -ne '' }) -join "`n"

        # Save the cleaned content back to file
        $cleanContent | Out-File -FilePath $filePath -Encoding UTF8 -NoNewline

        # Apply to cluster
        $applyResult = kubectl apply -f $filePath 2>&1
        $applyLines = ($applyResult -split "`n") | Where-Object { $_.Trim() -ne '' }

        if ($LASTEXITCODE -eq 0) {
            $statusMap = @{}
            foreach ($line in $applyLines) {
                if ($line -match 'ingress\.networking\.k8s\.io/([^\s]+)\s+(\w+)') {
                    $statusMap[$matches[1]] = $matches[2]
                }
            }

            foreach ($entry in $entries) {
                $name = $entry.Name
                $status = if ($statusMap.ContainsKey($name)) { $statusMap[$name] } else { '' }
                switch ($status) {
                    'created' {
                        Write-Host "  ✓ $($entry.Key) - berhasil dibuat" -ForegroundColor Green
                        $createdCount++
                    }
                    'configured' {
                        Write-Host "  ✓ $($entry.Key) - berhasil diupdate" -ForegroundColor Green
                        $updatedCount++
                    }
                    'unchanged' {
                        Write-Host "  ✓ $($entry.Key) - tidak ada perubahan" -ForegroundColor Green
                        $unchangedCount++
                    }
                    default {
                        if ($entry.Action -eq 'create') {
                            Write-Host "  ✓ $($entry.Key) - berhasil diproses (create)" -ForegroundColor Green
                            $createdCount++
                        } elseif ($entry.Action -eq 'update') {
                            Write-Host "  ✓ $($entry.Key) - berhasil diproses (update)" -ForegroundColor Green
                            $updatedCount++
                        } else {
                            Write-Host "  ✓ $($entry.Key) - berhasil diproses" -ForegroundColor Green
                            $unchangedCount++
                        }
                    }
                }
            }
        } else {
            $skipPatterns = @(
                'already defined in ingress',
                'already exists',
                'spec.rules\[\d+\].host: Invalid value'
            )

            $shouldSkip = $false
            foreach ($pattern in $skipPatterns) {
                if ($applyResult -match $pattern) {
                    $shouldSkip = $true
                    break
                }
            }

            if ($shouldSkip) {
                foreach ($entry in $entries) {
                    Write-Host "  ≈ $($entry.Key) - dilewati karena sudah ready" -ForegroundColor Yellow
                }
                $skippedCount += $entries.Count
            } else {
                Write-Host "  ✗ Gagal memproses file ${filePath}:" -ForegroundColor Red
                Write-Host $applyResult -ForegroundColor Red
                foreach ($entry in $entries) {
                    Write-Host "    ↳ $($entry.Key)" -ForegroundColor Red
                }
                $errorCount += $entries.Count
            }
        }
    }
}

Write-Host 'Deteksi ingress selesai.'

Write-Host "`nRingkasan sinkronisasi ingress:" -ForegroundColor Cyan
Write-Host "  - Dihapus   : $deletedCount"
Write-Host "  - Dibuat    : $createdCount"
Write-Host "  - Diperbarui: $updatedCount"
Write-Host "  - Tidak berubah: $unchangedCount"
Write-Host "  - Dilewati  : $skippedCount"
Write-Host "  - Error     : $errorCount"
