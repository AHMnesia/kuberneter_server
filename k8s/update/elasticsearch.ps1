# Helper to get the actual container name for a pod
function Get-ContainerNameForPod {
    param(
        [string]$namespace,
        [string]$podName
    )
    $podJson = kubectl get pod $podName -n $namespace -o json --ignore-not-found 2>$null
    if (-not $podJson) { return $null }
    $podObj = $podJson | ConvertFrom-Json
    if ($podObj.spec -and $podObj.spec.containers -and $podObj.spec.containers.Count -gt 0) {
        $names = $podObj.spec.containers | ForEach-Object { $_.name }
        Write-Host ('    Pod ' + $podName + ' containers: ' + ($names -join ', ')) -ForegroundColor Gray
        $esContainer = $names | Where-Object { $_ -match '(?i)es|search' }
        if ($esContainer) { return $esContainer | Select-Object -First 1 }
        return $names | Select-Object -First 1
    }
    return $null
}




# Set default values if not provided
if (-not $namespaceElasticsearch) { $namespaceElasticsearch = 'elasticsearch' }
if (-not $elasticUser) { $elasticUser = 'elastic' }
if (-not $clusterSoakSeconds) { $clusterSoakSeconds = 120 }

$ErrorActionPreference = 'Stop'



# Helper Functions
function Get-ReadyPodCount {
    param([string]$ns)
    $json = kubectl get pods -n $ns -l app=elasticsearch -o json --ignore-not-found 2>$null
    if (-not $json) { return 0 }
    $obj = $json | ConvertFrom-Json
    $count = 0
    foreach ($item in $obj.items) {
        if ($item.status -and $item.status.conditions) {
            $readyCond = $item.status.conditions | Where-Object { $_.type -eq 'Ready' -and $_.status -eq 'True' }
            if ($readyCond) { $count++ }
        }
    }
    return $count
}

function Get-ReadyPodNames {
    param([string]$ns)
    $json = kubectl get pods -n $ns -l app=elasticsearch -o json --ignore-not-found 2>$null
    if (-not $json) { return @() }
    $obj = $json | ConvertFrom-Json
    $readyPods = @()
    foreach ($item in $obj.items) {
        if ($item.status -and $item.status.conditions) {
            $readyCond = $item.status.conditions | Where-Object { $_.type -eq 'Ready' -and $_.status -eq 'True' }
            if ($readyCond) { $readyPods += $item.metadata.name }
        }
    }
    return $readyPods | Sort-Object { [int]($_.Split('-')[-1]) }
}

function Start-PortForwardJob {
    param([string]$ns)
    return Start-Job -ScriptBlock {
        param($namespace)
        kubectl port-forward svc/elasticsearch 9200:9200 -n $namespace *> $null
    } -ArgumentList $ns
}

function Wait-PortOpen {
    param(
        [int]$port,
        [string]$computerName = 'localhost',
        [int]$timeoutSeconds = 15
    )
    $elapsed = 0
    $result = $false
    
    Write-Host "  Waiting for port $port on $computerName to open (timeout: ${timeoutSeconds}s)..." -ForegroundColor Gray
    while ($elapsed -lt $timeoutSeconds) {
        try {
            if (Test-NetConnection -ComputerName $computerName -Port $port -InformationLevel Quiet) { 
                $result = $true
                break
            }
        } catch {
            # Ignore and retry
        }
        Start-Sleep -Seconds 1
        $elapsed++
    }
    
    if ($result) {
        Write-Host "  Port $port is now accessible" -ForegroundColor Gray
    } else {
        Write-Host "  Timed out waiting for port $port" -ForegroundColor Yellow
    }
    
    return $result
}

function Invoke-EsApi {
    param(
        [string]$namespace,
        [string]$encodedCredential,
        [string]$path,
        [string]$method = 'GET',
        $body = $null,
        [string]$excludePod = $null
    )

    if ($method -ne 'GET') {
        throw "Invoke-EsApi currently only supports GET method for health checks."
    }
    if ($body) {
        throw "Invoke-EsApi (GET) does not support request body."
    }

    $readyPods = Get-ReadyPodNames -ns $namespace
    if (-not $readyPods -or $readyPods.Count -eq 0) {
        throw "No ready Elasticsearch pods available for API call."
    }

    $candidates = if ($excludePod) {
        $readyPods | Where-Object { $_ -ne $excludePod }
    } else {
        $readyPods
    }
    if (-not $candidates -or $candidates.Count -eq 0) {
        $candidates = $readyPods
    }

    $uri = if ($path.StartsWith('/')) { "http://localhost:9200$path" } else { "http://localhost:9200/$path" }
    $curlCommand = "curl -sS -H 'Authorization: Basic $encodedCredential' '$uri'"

    foreach ($pod in $candidates) {
        try {
            $containerName = Get-ContainerNameForPod -namespace $namespace -podName $pod
            Write-Host ('  Using container name for pod ' + $pod + ': ' + $containerName) -ForegroundColor Gray
            # Delay to allow ES to start after pod ready
            Start-Sleep -Seconds 10
            $maxRetry = 3
            $retry = 0
            $raw = $null
            while ($retry -lt $maxRetry) {
                if ($containerName) {
                    $raw = & kubectl exec -n $namespace $pod -c $containerName -- sh -c $curlCommand 2>$null
                } else {
                    $raw = & kubectl exec -n $namespace $pod -- sh -c $curlCommand 2>$null
                }
                if ($LASTEXITCODE -eq 0 -and $raw) {
                    break
                }
                Write-Host ('    Retry ' + ($retry+1) + ' failed for pod ' + $pod) -ForegroundColor Gray
                Start-Sleep -Seconds 5
                $retry++
            }
            if ($LASTEXITCODE -ne 0 -or -not $raw) {
                throw "Invoke curl returned empty response"
            }
            return $raw | ConvertFrom-Json
        } catch {
            Write-Host ('  Failed to call Elasticsearch API from pod ' + $pod + ': ' + $_.Exception.Message) -ForegroundColor Gray
        }
    }
    throw "All attempts to call Elasticsearch API failed."
}

function Wait-ClusterHealth {
    param(
        [string]$namespace,
        [string]$encodedCredential,
        [int]$expectedNodes,
        [int]$timeoutSeconds = 300,
        [string]$excludePod = $null
    )

    $deadline = (Get-Date).AddSeconds($timeoutSeconds)
    Write-Host "  Waiting for cluster health (yellow or green) with $expectedNodes nodes (timeout: ${timeoutSeconds}s)..." -ForegroundColor Gray
    
    while ((Get-Date) -lt $deadline) {
        try {
            $result = Invoke-EsApi -namespace $namespace -encodedCredential $encodedCredential -path "/_cluster/health?wait_for_status=yellow&timeout=10s" -excludePod $excludePod
            if ($result -and $result.number_of_nodes -ge $expectedNodes -and ($result.status -eq 'yellow' -or $result.status -eq 'green')) {
                Write-Host "  Cluster health: status=$($result.status), nodes=$($result.number_of_nodes)" -ForegroundColor Gray
                return $true
            }
            if ($result) {
                Write-Host "  Cluster health not yet stable (status=$($result.status), nodes=$($result.number_of_nodes))." -ForegroundColor Gray
            }
        } catch {
            Write-Host "  Cluster health check failed: $($_.Exception.Message)" -ForegroundColor Gray
        }
        Start-Sleep -Seconds 5
    }
    
    Write-Host "  Timed out waiting for cluster health" -ForegroundColor Yellow
    return $false
}

function Wait-ClusterSteadyState {
    param(
        [string]$namespace,
        [string]$encodedCredential,
        [int]$expectedNodes,
        [int]$soakSeconds = 30,
        [int]$timeoutSeconds = 300,
        [string]$excludePod = $null
    )

    if ($soakSeconds -le 0) { return $true }

    $deadline = (Get-Date).AddSeconds($timeoutSeconds)
    $stableAccumulated = 0
    
    Write-Host "  Waiting for cluster steady state for ${soakSeconds}s (timeout: ${timeoutSeconds}s)..." -ForegroundColor Gray
    
    while ((Get-Date) -lt $deadline) {
        try {
            $health = Invoke-EsApi -namespace $namespace -encodedCredential $encodedCredential -path "/_cluster/health" -excludePod $excludePod
            $root = Invoke-EsApi -namespace $namespace -encodedCredential $encodedCredential -path "/" -excludePod $excludePod
            $activePercent = 0
            if ($health -and $health.PSObject.Properties.Name -contains 'active_shards_percent_as_number') {
                $activePercent = [double]$health.active_shards_percent_as_number
            }
            $statusOk = $health -and $health.number_of_nodes -ge $expectedNodes -and ($health.status -eq 'yellow' -or $health.status -eq 'green') -and $activePercent -ge 100
            $httpOk = $root -ne $null
            if ($statusOk -and $httpOk) {
                $stableAccumulated += 5
                if ($stableAccumulated -ge $soakSeconds) {
                    Write-Host "  Cluster remained stable for $stableAccumulated seconds." -ForegroundColor Gray
                    return $true
                }
            } else {
                $stableAccumulated = 0
                if ($health) {
                    Write-Host "  Steady state reset (status=$($health.status), active_shards=$($health.active_shards_percent_as_number))." -ForegroundColor Gray
                } else {
                    Write-Host "  Steady state reset (health check failed)." -ForegroundColor Gray
                }
            }
        } catch {
            $stableAccumulated = 0
            Write-Host "  Steady state check failed: $($_.Exception.Message)" -ForegroundColor Gray
        }
        Start-Sleep -Seconds 5
    }
    Write-Host "  Failed to reach cluster steady state within $timeoutSeconds seconds." -ForegroundColor Yellow
    return $false
}

function Import-BulkData {
    param(
        [string]$filePath,
        [string]$indexName,
        [string]$elasticUser,
        [string]$elasticPassword,
        [string]$namespace
    )
    
    Write-Host "Setting up port-forward for Elasticsearch..." -ForegroundColor Yellow
    $portForwardJob = Start-PortForwardJob -ns $namespace
    
    try {
        if (-not (Wait-PortOpen -port 9200 -timeoutSeconds 20)) {
            throw "Port-forward could not be established. Ensure there's a ready Elasticsearch pod."
        }
        
        Write-Host "Importing data from $filePath to index $indexName..." -ForegroundColor Yellow
        curl -u "${elasticUser}:${elasticPassword}" -X POST "http://localhost:9200/_bulk" -H "Content-Type: application/x-ndjson" --data-binary "@$filePath"
        
        if ($LASTEXITCODE -eq 0) {
            Write-Host "Data import completed successfully." -ForegroundColor Green
            return $true
        } else {
            throw "curl command failed with exit code $LASTEXITCODE"
        }
    }
    catch {
        Write-Host "Error importing data: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
    finally {
        if ($portForwardJob) {
            Stop-Job $portForwardJob -ErrorAction SilentlyContinue
            Remove-Job $portForwardJob -ErrorAction SilentlyContinue
            Write-Host "Port-forward connection closed." -ForegroundColor Gray
        }
    }
}

function Import-Data {
    param(
        [string]$filePath,
        [string]$fileType,
        [string]$indexName,
        [string]$elasticUser,
        [string]$elasticPassword,
        [string]$namespace
    )
    
    Write-Host "Connecting to remote Elasticsearch at search.suma-honda.local..." -ForegroundColor Yellow
    
    try {
        Write-Host "Importing $fileType data from $filePath to index $indexName..." -ForegroundColor Yellow
        
        if ($fileType -eq "CSV" -and (Get-Command elasticsearch-loader -ErrorAction SilentlyContinue)) {
            elasticsearch-loader --es-host https://search.suma-honda.local --user $elasticUser --password $elasticPassword --index $indexName --type _doc csv $filePath
            if ($LASTEXITCODE -ne 0) {
                throw "elasticsearch-loader failed with exit code $LASTEXITCODE"
            }
        } 
        else {
            Write-Host "Using curl method for bulk import..." -ForegroundColor Yellow
            if ($fileType -eq "JSON") {
                # For JSON files, assume NDJSON format (one JSON object per line)
                $bulkResponse = & curl.exe -k -s -u "${elasticUser}:${elasticPassword}" -X POST "https://search.suma-honda.local/_bulk" -H "Content-Type: application/x-ndjson" --data-binary "@$filePath" 2>$null
            } else {
                # For CSV or other formats, try to use curl with NDJSON expectation
                $bulkResponse = & curl.exe -k -s -u "${elasticUser}:${elasticPassword}" -X POST "https://search.suma-honda.local/_bulk" -H "Content-Type: application/x-ndjson" --data-binary "@$filePath" 2>$null
            }
            
            if ($LASTEXITCODE -ne 0) {
                throw "curl command failed with exit code $LASTEXITCODE"
            }
            
            # Parse bulk response to check for errors
            try {
                $bulkResult = $bulkResponse | ConvertFrom-Json
                if ($bulkResult.errors -eq $true) {
                    $errorCount = ($bulkResult.items | Where-Object { $_.index.error }).Count
                    Write-Host "Bulk import completed with $errorCount errors. Check Elasticsearch logs for details." -ForegroundColor Yellow
                } else {
                    $successCount = $bulkResult.items.Count
                    Write-Host "Successfully imported $successCount documents." -ForegroundColor Green
                }
            } catch {
                Write-Host "Warning: Could not parse bulk import response. Import may have succeeded." -ForegroundColor Yellow
            }
        }
        
        Write-Host "Data import completed successfully." -ForegroundColor Green
        return $true
    }
    catch {
        Write-Host "Error importing data: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

#
# Main Script Logic
#

# Check kubectl availability
if (-not (Get-Command kubectl -ErrorAction SilentlyContinue)) {
    Write-Host "ERROR: 'kubectl' not found in PATH. Install kubectl or add it to PATH before running this script." -ForegroundColor Red
    exit 1
}

Write-Host "Using namespace: $namespaceElasticsearch" -ForegroundColor Cyan

# Main menu
Write-Host "`nSelect operation:" -ForegroundColor Cyan
Write-Host "1. Restart Elasticsearch" -ForegroundColor White
Write-Host "2. Data Operations" -ForegroundColor White
$choice = Read-Host "Enter choice (1 or 2)"

if ($choice -eq "1") {
    Write-Host "Proceeding with Elasticsearch restart..." -ForegroundColor Green
    
    # Use relative paths based on this script location so the repo can move
    $root = Split-Path $PSScriptRoot -Parent
    $esDir = Join-Path $root 'elasticsearch'

    Write-Host "Applying latest Elasticsearch manifests (if present) from: $esDir" -ForegroundColor Cyan
    try {
        $files = @('deployment.yaml','service.yaml','statefulset.yaml') | ForEach-Object { Join-Path $esDir $_ }
        foreach ($f in $files) {
            if (Test-Path $f) {
                Write-Host "  Applying $f" -ForegroundColor Gray
                kubectl apply -f $f -n $namespaceElasticsearch
                if ($LASTEXITCODE -ne 0) { Write-Host "  Warning: kubectl apply returned non-zero for $f" -ForegroundColor Yellow }
            }
        }
    } catch {
        Write-Host "Warning: Failed to apply elasticsearch manifests: $_" -ForegroundColor Yellow
    }

    # Check for StatefulSet or Deployment existence
    $ss = kubectl get statefulset elasticsearch -n $namespaceElasticsearch --ignore-not-found -o name 2>$null
    $dep = kubectl get deployment elasticsearch -n $namespaceElasticsearch --ignore-not-found -o name 2>$null

    # Perform per-pod restart
    Write-Host "Performing per-pod restart to minimize downtime (label: app=elasticsearch)." -ForegroundColor Yellow
    $podsJson = kubectl get pods -n $namespaceElasticsearch -l app=elasticsearch -o json --ignore-not-found 2>$null
    if (-not $podsJson) {
        Write-Host "No pods found with label app=elasticsearch in namespace $namespaceElasticsearch" -ForegroundColor Yellow
        exit 0
    }
    $podsObj = $podsJson | ConvertFrom-Json
    Write-Host "Manual Elasticsearch pod restart mode..." -ForegroundColor Green
            $podsJson = kubectl get pods -n $namespaceElasticsearch -l app=elasticsearch -o json --ignore-not-found 2>$null
            if (-not $podsJson) {
                Write-Host "No pods found with label app=elasticsearch in namespace $namespaceElasticsearch" -ForegroundColor Yellow
                exit 0
            }
            $podsObj = $podsJson | ConvertFrom-Json
            Write-Host "\nList of Elasticsearch pods:" -ForegroundColor Cyan
            $podIndex = 0
            foreach ($p in $podsObj.items) {
                $podName = $p.metadata.name
                $readyCond = $p.status.conditions | Where-Object { $_.type -eq 'Ready' -and $_.status -eq 'True' }
                $readyStatus = if ($readyCond) { 'Ready' } else { 'NotReady' }
                Write-Host ("$podIndex. " + $podName + " : " + $readyStatus) -ForegroundColor White
                $podIndex++
            }
            $selectedIndex = Read-Host "\nEnter pod number to restart (0-$($podIndex-1))"
            if (-not ($selectedIndex -match '^\d+$') -or [int]$selectedIndex -lt 0 -or [int]$selectedIndex -ge $podIndex) {
                Write-Host "Invalid pod number: $selectedIndex" -ForegroundColor Red
                exit 1
            }
            $selectedPod = $podsObj.items[[int]$selectedIndex].metadata.name
            Write-Host "Deleting pod $selectedPod (grace 30s) to trigger replacement..." -ForegroundColor Yellow
            kubectl delete pod $selectedPod -n $namespaceElasticsearch --grace-period=30 --wait=false
            # Wait for the specific pod to be replaced and ready
            $timeout = 600
            $elapsed = 0
            $replacementReady = $false
            while ($elapsed -lt $timeout) {
                Start-Sleep -Seconds 5
                $elapsed += 5
                $podJson = kubectl get pod $selectedPod -n $namespaceElasticsearch -o json --ignore-not-found 2>$null
                if ($podJson) {
                    $podObj = $podJson | ConvertFrom-Json
                    if ($podObj.status -and $podObj.status.conditions) {
                        $readyCond = $podObj.status.conditions | Where-Object { $_.type -eq 'Ready' -and $_.status -eq 'True' }
                        if ($readyCond) {
                            $replacementReady = $true
                            Write-Host "Pod $selectedPod is now ready." -ForegroundColor Green
                            break
                        }
                    }
                }
                Write-Host "  Waiting for pod $selectedPod to be ready... ($elapsed/$timeout seconds)" -ForegroundColor Gray
            }
            if (-not $replacementReady) { 
                Write-Host "Timeout waiting for pod $selectedPod to become ready" -ForegroundColor Red
                exit 1
            }
            Write-Host "Pod $selectedPod successfully restarted and ready." -ForegroundColor Green
            exit 0
}
elseif ($choice -eq "2") {
    Write-Host "Data Operations - Import data into Elasticsearch from elasticsearch/data/ directory" -ForegroundColor Cyan
    
    # Prompt for Elasticsearch credentials
    if (-not $elasticUser) {
        $elasticUser = Read-Host "Enter Elasticsearch username (default: elastic)"
        if ([string]::IsNullOrWhiteSpace($elasticUser)) {
            $elasticUser = 'elastic'
        }
    }
    
    if (-not $elasticPassword) {
        $elasticPassword = Read-Host "Enter Elasticsearch password" -AsSecureString
        $elasticPassword = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($elasticPassword))
    }

    if (-not $elasticPassword) {
        throw "Elasticsearch password is required for data operations."
    }

    # Test Elasticsearch connection and credentials
    Write-Host "Testing Elasticsearch connection and credentials..." -ForegroundColor Yellow
    try {
        # Test credentials with a simple API call to remote Elasticsearch
        # Use -f flag to make curl fail on HTTP errors
        $testResponse = & curl.exe -k -s -f -u "${elasticUser}:${elasticPassword}" "https://search.suma-honda.local/_cluster/health" 2>$null
        if ($LASTEXITCODE -ne 0) {
            throw "Authentication failed. Please check your Elasticsearch username and password."
        }
        
        $health = $testResponse | ConvertFrom-Json
        if (-not $health) {
            throw "Invalid response from Elasticsearch. Please check your credentials."
        }
        
        # Check if response contains error (authentication failed, etc.)
        if ($health.error) {
            $errorReason = $health.error.reason
            throw "Authentication failed: $errorReason"
        }
        
        # Check if this is a valid cluster health response
        if (-not $health.status -or ($health.status -ne 'yellow' -and $health.status -ne 'green' -and $health.status -ne 'red')) {
            throw "Invalid cluster health response. Expected status yellow/green/red, got: $($health.status)"
        }
        
        Write-Host "Elasticsearch connection successful. Cluster status: $($health.status)" -ForegroundColor Green
    }
    catch {
        Write-Host "Connection test failed: $($_.Exception.Message)" -ForegroundColor Red
        exit 1
    }
    
    # Scan for data files in elasticsearch/data/ directory
    $dataDir = Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) "elasticsearch\data"
    
    if (-not (Test-Path $dataDir)) {
        Write-Host "Data directory not found: $dataDir" -ForegroundColor Red
        exit 1
    }
    
    $dataFiles = Get-ChildItem -Path $dataDir -File | Where-Object { $_.Extension -eq '.json' -or $_.Extension -eq '.csv' }
    
    if (-not $dataFiles -or $dataFiles.Count -eq 0) {
        Write-Host "No .json or .csv files found in $dataDir" -ForegroundColor Red
        Write-Host "Please place your data files (.json or .csv) in the elasticsearch/data/ directory." -ForegroundColor Yellow
        exit 1
    }
    
    Write-Host "`nAvailable data files:" -ForegroundColor Cyan
    $fileIndex = 1
    foreach ($file in $dataFiles) {
        $fileType = if ($file.Extension -eq '.json') { 'JSON' } else { 'CSV' }
        Write-Host "$fileIndex. $($file.Name) ($fileType)" -ForegroundColor White
        $fileIndex++
    }
    
    $selectedIndex = Read-Host "`nEnter file number to import (1-$($fileIndex-1))"
    
    if (-not ($selectedIndex -match '^\d+$') -or [int]$selectedIndex -lt 1 -or [int]$selectedIndex -ge $fileIndex) {
        Write-Host "Invalid file number: $selectedIndex" -ForegroundColor Red
        exit 1
    }
    
    $selectedFile = $dataFiles[[int]$selectedIndex - 1]
    $filePath = $selectedFile.FullName
    $fileType = if ($selectedFile.Extension -eq '.json') { 'JSON' } else { 'CSV' }
    
    Write-Host "Selected file: $($selectedFile.Name) ($fileType)" -ForegroundColor Green
    
    # Handle index creation vs data import
    if ($selectedFile.Name -eq 'createIndexProduk.json' -or $selectedFile.Name -eq 'createindex.json' -or $selectedFile.Name -eq 'createIndexCategori.json') {
        Write-Host "Creating Elasticsearch index from configuration file..." -ForegroundColor Yellow
        
        try {
            $indexConfig = Get-Content $filePath -Raw | ConvertFrom-Json
            $indexName = $indexConfig.index_name
            
            if ([string]::IsNullOrWhiteSpace($indexName)) {
                Write-Host "Index name not found in configuration file." -ForegroundColor Red
                exit 1
            }
            
            Write-Host "Creating index: $indexName" -ForegroundColor Cyan
            
            # Remove index_name from config before sending to Elasticsearch
            $esConfig = $indexConfig | Select-Object -Property * -ExcludeProperty index_name
            
            # Create index using PUT request
            # Create temporary file with JSON data to avoid PowerShell variable expansion issues
            $tempFile = [System.IO.Path]::GetTempFileName()
            try {
                $esConfig | ConvertTo-Json -Depth 10 -Compress | Out-File -FilePath $tempFile -Encoding UTF8
                $createResponse = & curl.exe -k -s -f -X PUT -u "${elasticUser}:${elasticPassword}" "https://search.suma-honda.local/$indexName" -H "Content-Type: application/json" "-d@$tempFile" 2>$null
            } finally {
                # Clean up temp file
                if (Test-Path $tempFile) {
                    Remove-Item $tempFile -Force
                }
            }
            
            if ($LASTEXITCODE -eq 0) {
                $result = $createResponse | ConvertFrom-Json
                if ($result.acknowledged -eq $true) {
                    Write-Host "Index '$indexName' created successfully." -ForegroundColor Green
                    exit 0
                } else {
                    Write-Host "Failed to create index. Response: $($createResponse)" -ForegroundColor Red
                    exit 1
                }
            } else {
                # Try to parse error response
                try {
                    $errorResult = $createResponse | ConvertFrom-Json
                    if ($errorResult.error) {
                        Write-Host "Failed to create index: $($errorResult.error.reason)" -ForegroundColor Red
                        if ($errorResult.error.causes) {
                            Write-Host "Details: $($errorResult.error.causes[0].reason)" -ForegroundColor Yellow
                        }
                    } else {
                        Write-Host "Failed to create index. HTTP Status: $LASTEXITCODE" -ForegroundColor Red
                    }
                } catch {
                    Write-Host "Failed to create index. curl exit code: $LASTEXITCODE" -ForegroundColor Red
                    Write-Host "Raw response: $createResponse" -ForegroundColor Yellow
                }
                exit 1
            }
        }
        catch {
            Write-Host "Error creating index: $($_.Exception.Message)" -ForegroundColor Red
            exit 1
        }
    } else {
        # Check if file already contains bulk API format with index information
        $firstLine = Get-Content $filePath -First 1
        $hasBulkFormat = $firstLine -match '"index"' -and $firstLine -match '"_index"'
        
        if ($hasBulkFormat) {
            Write-Host "File contains bulk API format with index information. Importing directly..." -ForegroundColor Green
            
            # Extract index name from the first bulk operation
            try {
                $firstIndexOp = $firstLine | ConvertFrom-Json
                $bulkIndexName = $firstIndexOp.index._index
                Write-Host "Detected index name from bulk data: $bulkIndexName" -ForegroundColor Cyan
                
                # Check if index exists before importing
                $indexCheckResponse = & curl.exe -k -s -u "${elasticUser}:${elasticPassword}" "https://search.suma-honda.local/$bulkIndexName" 2>$null
                if ($LASTEXITCODE -ne 0) {
                    Write-Host "ERROR: Index '$bulkIndexName' does not exist. Please create the index first using a configuration file." -ForegroundColor Red
                    Write-Host "Available index configuration files:" -ForegroundColor Yellow
                    Get-ChildItem "c:\docker\elasticsearch\data\createIndex*.json" | ForEach-Object {
                        Write-Host "  - $($_.Name)" -ForegroundColor Cyan
                    }
                    exit 1
                }
                
                $indexInfo = $indexCheckResponse | ConvertFrom-Json
                if ($indexInfo.error) {
                    Write-Host "ERROR: Index '$bulkIndexName' does not exist. Please create the index first." -ForegroundColor Red
                    exit 1
                }
                
                Write-Host "Index '$bulkIndexName' exists. Proceeding with data import..." -ForegroundColor Green
                $indexName = $bulkIndexName
            } catch {
                Write-Host "ERROR: Could not parse bulk data format or check index existence." -ForegroundColor Red
                exit 1
            }
        } else {
            $indexName = Read-Host "Enter Elasticsearch index name (example: my_index)"
        }
        
        if (Import-Data -filePath $filePath -fileType $fileType -indexName $indexName -elasticUser $elasticUser -elasticPassword $elasticPassword -namespace $namespaceElasticsearch) {
            exit 0
        } else {
            exit 1
        }
    }
}
