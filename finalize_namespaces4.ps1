param(
  [string[]]$Namespaces = @('suma-android','suma-ecommerce','suma-office','suma-office-general','suma-pmo')
)

foreach ($ns in $Namespaces) {
  Write-Host "\n=== Finalizing namespace: $ns ==="
  try {
    $obj = @{ apiVersion = 'v1'; kind = 'Namespace'; metadata = @{ name = $ns; finalizers = @() } }
    $tmp = Join-Path $env:TEMP ("$ns-finalize.json")
    $json = $obj | ConvertTo-Json -Depth 10
    # write UTF8 without BOM
    $enc = New-Object System.Text.UTF8Encoding $false
    [System.IO.File]::WriteAllText($tmp, $json, $enc)
    Write-Host "Posting finalize payload for $ns"
    $res = kubectl replace --raw "/api/v1/namespaces/$ns/finalize" -f $tmp 2>&1
    Write-Host $res
    Remove-Item $tmp -ErrorAction SilentlyContinue
  } catch {
    Write-Host ("Error finalizing {0}: {1}" -f $ns, $_)
  }
}

Write-Host "\n=== Namespaces now ==="
kubectl get namespaces -o wide

Write-Host "\nFinalize script finished."