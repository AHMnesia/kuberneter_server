param(
  [string]$ElasticsearchDomain = 'search.suma-honda.local',
  [string]$ElasticsearchUser = 'elastic',
  [string]$ElasticsearchPass = 'admin123',
  [int]$MaxWaitSeconds = 300,
  [int]$CheckIntervalSeconds = 5
)

Write-Host "=== Proses: Deteksi Koneksi Elasticsearch via Domain ===" -ForegroundColor Cyan

function Test-CurlExists {
  $curlPath = Get-Command curl.exe -ErrorAction SilentlyContinue
  if (-not $curlPath) {
    Write-Host "Error: curl tidak ditemukan di PATH. Pastikan curl sudah terinstall." -ForegroundColor Red
    exit 1
  }
}

function Wait-ForElasticsearch {
  param(
    [string]$Domain,
    [string]$User,
    [string]$Pass,
    [int]$MaxWait = 180,
    [int]$Interval = 5
  )
  $elapsed = 0
  while ($elapsed -lt $MaxWait) {
    $remaining = $MaxWait - $elapsed
    Write-Host ("Coba akses Elasticsearch di https://{0}/_cluster/health ... (sisa {1} detik)" -f $Domain, $remaining) -ForegroundColor DarkCyan
    $cmd = 'curl.exe -k -u ' + $User + ':' + $Pass + ' -s -o /dev/null -w "%{http_code}" https://' + $Domain + '/_cluster/health'
    $status = Invoke-Expression $cmd
    if ($status -eq '200') {
      Write-Host "Elasticsearch cluster health is accessible at https://$Domain/_cluster/health" -ForegroundColor Green
      return $true
    }
    else {
      Write-Host "Belum bisa akses Elasticsearch cluster health (status: $status), tunggu dan coba lagi..." -ForegroundColor Yellow
    }
    Start-Sleep -Seconds $Interval
    $elapsed += $Interval
  }
  Write-Host "Timeout: Elasticsearch cluster health is not accessible after $MaxWait seconds." -ForegroundColor Red
  return $false
}

Test-CurlExists
Write-Host "=== Mulai proses tunggu Elasticsearch ===" -ForegroundColor Cyan
$result = Wait-ForElasticsearch -Domain $ElasticsearchDomain -User $ElasticsearchUser -Pass $ElasticsearchPass -MaxWait $MaxWaitSeconds -Interval $CheckIntervalSeconds
if ($result) {
  Write-Host "=== Elasticsearch sudah siap diakses! ===" -ForegroundColor Green
  Write-Host "Mengecek status cluster Elasticsearch sebelum membuat user..." -ForegroundColor Cyan

  # Tunggu hingga cluster health berstatus yellow atau green sebelum menulis user
  $elapsedHealth = 0
  $healthOk = $false
  while ($elapsedHealth -lt $MaxWaitSeconds) {
    Write-Host ("Memeriksa _cluster/health (sisa {0}s)..." -f ($MaxWaitSeconds - $elapsedHealth)) -ForegroundColor DarkCyan
    $healthCmd = 'curl.exe -k -u ' + $ElasticsearchUser + ':' + $ElasticsearchPass + ' -s "https://' + $ElasticsearchDomain + '/_cluster/health?wait_for_status=yellow&timeout=1s"'
    $healthOut = Invoke-Expression $healthCmd
    try {
      $healthJson = $healthOut | ConvertFrom-Json
      if ($healthJson -and $healthJson.status) {
        Write-Host ("Cluster status: {0}" -f $healthJson.status) -ForegroundColor Green
        if ($healthJson.status -in @('yellow','green')) { $healthOk = $true; break }
      }
    } catch {
      Write-Host 'Gagal parse response cluster health, menunggu...' -ForegroundColor Yellow
    }
    Start-Sleep -Seconds $CheckIntervalSeconds
    $elapsedHealth += $CheckIntervalSeconds
  }

  if (-not $healthOk) {
    Write-Host 'Cluster Elasticsearch belum pulih (status != yellow/green) setelah timeout. Tidak mencoba membuat user.' -ForegroundColor Red
    exit 1
  }

  Write-Host "Membuat user kibana_user di Elasticsearch..." -ForegroundColor Cyan
  $body = '{"password":"kibanapass","roles":["kibana_system"]}'
  $bodyFile = "$PSScriptRoot\\body.json"
  Set-Content -Path $bodyFile -Value $body
  $cmdCreate = 'curl.exe -k -u ' + $ElasticsearchUser + ':' + $ElasticsearchPass + ' -X POST "https://' + $ElasticsearchDomain + '/_security/user/kibana_user" -H "Content-Type: application/json" -d @' + $bodyFile
  Write-Host "Request: $cmdCreate" -ForegroundColor Gray
  $resultCreate = Invoke-Expression $cmdCreate
  Write-Host "Response: $resultCreate" -ForegroundColor White
  if ($resultCreate -match '"created":true') {
    Write-Host "User kibana_user berhasil dibuat di Elasticsearch." -ForegroundColor Green
  } elseif ($resultCreate -match '"created":false') {
    Write-Host "User kibana_user sudah ada di Elasticsearch." -ForegroundColor Yellow
  } else {
    Write-Host "Gagal membuat user kibana_user. Cek detail response di atas." -ForegroundColor Red
  }
  Remove-Item $bodyFile -Force
}
else {
  Write-Host "=== Gagal akses Elasticsearch. Silakan cek konfigurasi dan jaringan. ===" -ForegroundColor Red
  exit 1
}