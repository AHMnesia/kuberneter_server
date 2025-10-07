# Create Kibana User in Elasticsearch
# Usage: .\create-kibana-user.ps1 [-ElasticsearchDomain <domain>] [-ElasticsearchUser <user>] [-ElasticsearchPass <pass>]

param(
    [string]$ElasticsearchDomain = 'search.suma-honda.local',
    [string]$ElasticsearchUser = 'elastic',
    [string]$ElasticsearchPass = 'admin123',
    [string]$KibanaUserName = 'kibana_user',
    [string]$KibanaUserPass = 'kibanapass',
    [int]$MaxWaitSeconds = 300,
    [int]$CheckIntervalSeconds = 5
)

$ErrorActionPreference = "Continue"

# Color functions
function Write-Status {
    param([string]$Message)
    Write-Host "[+] $Message" -ForegroundColor Green
}

function Write-CustomWarning {
    param([string]$Message)
    Write-Host "[!] $Message" -ForegroundColor Yellow
}

function Write-CustomError {
    param([string]$Message)
    Write-Host "[x] $Message" -ForegroundColor Red
}

function Write-Info {
    param([string]$Message)
    Write-Host "[i] $Message" -ForegroundColor Cyan
}

Write-Host ""
Write-Host "================================" -ForegroundColor Cyan
Write-Host "Create Kibana User in Elasticsearch" -ForegroundColor Cyan
Write-Host "================================" -ForegroundColor Cyan
Write-Host ""

Write-Info "Configuration:"
Write-Host "  Elasticsearch Domain: $ElasticsearchDomain" -ForegroundColor Gray
Write-Host "  Elasticsearch User:   $ElasticsearchUser" -ForegroundColor Gray
Write-Host "  Kibana User:          $KibanaUserName" -ForegroundColor Gray
Write-Host "  Max Wait:             $MaxWaitSeconds seconds" -ForegroundColor Gray
Write-Host ""

# Check curl exists
function Test-CurlExists {
    $curlPath = Get-Command curl.exe -ErrorAction SilentlyContinue
    if (-not $curlPath) {
        Write-CustomError "curl not found in PATH"
        Write-Info "Install curl first or use Windows 10+ built-in curl"
        exit 1
    }
    Write-Status "curl found: $($curlPath.Source)"
}

# Wait for Elasticsearch to be ready
function Wait-ForElasticsearch {
    param(
        [string]$Domain,
        [string]$User,
        [string]$Pass,
        [int]$MaxWait,
        [int]$Interval
    )
    
    $elapsed = 0
    Write-Info "Waiting for Elasticsearch to be ready..."
    
    while ($elapsed -lt $MaxWait) {
        $remaining = $MaxWait - $elapsed
        Write-Host "  Checking https://$Domain/ ... (remaining: $remaining seconds)" -ForegroundColor DarkGray
        
        try {
            $cmd = "curl.exe -k -u ${User}:${Pass} -s -o `$null -w `"%{http_code}`" https://${Domain}/"
            $status = Invoke-Expression $cmd 2>$null
            
            if ($status -eq '200') {
                Write-Status "Elasticsearch is accessible at https://$Domain/"
                return $true
            }
            else {
                Write-Host "  Status: $status (not ready yet)" -ForegroundColor DarkYellow
            }
        }
        catch {
            Write-Host "  Connection failed, retrying..." -ForegroundColor DarkYellow
        }
        
        Start-Sleep -Seconds $Interval
        $elapsed += $Interval
    }
    
    Write-CustomError "Timeout: Elasticsearch not accessible after $MaxWait seconds"
    return $false
}

# Create Kibana user
function New-KibanaUser {
    param(
        [string]$Domain,
        [string]$User,
        [string]$Pass,
        [string]$KibanaUser,
        [string]$KibanaPass
    )
    
    Write-Info "Creating Kibana user '$KibanaUser' in Elasticsearch..."
    
    # Prepare request body
    $body = @{
        password = $KibanaPass
        roles = @("kibana_system")
    } | ConvertTo-Json -Compress
    
    # Create temp file for body
    $bodyFile = Join-Path $env:TEMP "kibana-user-body.json"
    $body | Out-File -FilePath $bodyFile -Encoding UTF8 -NoNewline
    
    try {
        # Execute curl command
        $url = "https://${Domain}/_security/user/${KibanaUser}"
        $cmd = "curl.exe -k -u ${User}:${Pass} -X POST `"${url}`" -H `"Content-Type: application/json`" -d @`"${bodyFile}`""
        
        Write-Host "  Request URL: $url" -ForegroundColor DarkGray
        Write-Host "  Request Body: $body" -ForegroundColor DarkGray
        
        $result = Invoke-Expression $cmd 2>&1
        
        Write-Host "  Response: $result" -ForegroundColor Gray
        
        # Check result
        if ($result -match '"created"\s*:\s*true') {
            Write-Status "Kibana user '$KibanaUser' created successfully"
            return $true
        }
        elseif ($result -match '"created"\s*:\s*false' -or $result -match 'already exists') {
            Write-CustomWarning "Kibana user '$KibanaUser' already exists"
            return $true
        }
        elseif ($result -match '"updated"\s*:\s*true') {
            Write-Status "Kibana user '$KibanaUser' updated successfully"
            return $true
        }
        else {
            Write-CustomError "Failed to create Kibana user"
            Write-Info "Response details: $result"
            return $false
        }
    }
    catch {
        Write-CustomError "Error creating Kibana user: $_"
        return $false
    }
    finally {
        # Clean up temp file
        if (Test-Path $bodyFile) {
            Remove-Item $bodyFile -Force -ErrorAction SilentlyContinue
        }
    }
}

# Verify user was created
function Test-KibanaUser {
    param(
        [string]$Domain,
        [string]$User,
        [string]$Pass,
        [string]$KibanaUser
    )
    
    Write-Info "Verifying Kibana user '$KibanaUser'..."
    
    try {
        $url = "https://${Domain}/_security/user/${KibanaUser}"
        $cmd = "curl.exe -k -u ${User}:${Pass} -s `"${url}`""
        
        $result = Invoke-Expression $cmd 2>&1
        
        if ($result -match '"kibana_system"' -or $result -match $KibanaUser) {
            Write-Status "Kibana user verified successfully"
            Write-Host "  User info: $result" -ForegroundColor Gray
            return $true
        }
        else {
            Write-CustomWarning "Could not verify Kibana user"
            return $false
        }
    }
    catch {
        Write-CustomWarning "Error verifying Kibana user: $_"
        return $false
    }
}

# Main execution
try {
    # Check prerequisites
    Test-CurlExists
    
    # Wait for Elasticsearch
    Write-Host ""
    $esReady = Wait-ForElasticsearch -Domain $ElasticsearchDomain -User $ElasticsearchUser -Pass $ElasticsearchPass -MaxWait $MaxWaitSeconds -Interval $CheckIntervalSeconds
    
    if (-not $esReady) {
        Write-CustomError "Elasticsearch is not accessible"
        Write-Info "Check:"
        Write-Host "  1. Elasticsearch pod is running: kubectl get pods -n elasticsearch" -ForegroundColor Gray
        Write-Host "  2. Service is accessible: kubectl get svc -n elasticsearch" -ForegroundColor Gray
        Write-Host "  3. Ingress is configured: kubectl get ingress -n elasticsearch" -ForegroundColor Gray
        Write-Host "  4. Domain is resolvable: nslookup $ElasticsearchDomain" -ForegroundColor Gray
        Write-Host "  5. Hosts file configured: C:\Windows\System32\drivers\etc\hosts" -ForegroundColor Gray
        exit 1
    }
    
    # Create Kibana user
    Write-Host ""
    $createSuccess = New-KibanaUser -Domain $ElasticsearchDomain -User $ElasticsearchUser -Pass $ElasticsearchPass -KibanaUser $KibanaUserName -KibanaPass $KibanaUserPass
    
    if (-not $createSuccess) {
        Write-CustomError "Failed to create Kibana user"
        exit 1
    }
    
    # Verify user
    Write-Host ""
    Test-KibanaUser -Domain $ElasticsearchDomain -User $ElasticsearchUser -Pass $ElasticsearchPass -KibanaUser $KibanaUserName
    
    # Success
    Write-Host ""
    Write-Host "================================" -ForegroundColor Green
    Write-Status "Kibana User Setup Complete!"
    Write-Host "================================" -ForegroundColor Green
    Write-Host ""
    Write-Host "Kibana Configuration:" -ForegroundColor Cyan
    Write-Host "  Username: $KibanaUserName" -ForegroundColor White
    Write-Host "  Password: $KibanaUserPass" -ForegroundColor White
    Write-Host "  Role:     kibana_system" -ForegroundColor White
    Write-Host ""
    Write-Info "Update Kibana configuration with these credentials"
    Write-Host "  kubectl edit configmap kibana-config -n kibana" -ForegroundColor Gray
    Write-Host "  or update values.yaml and redeploy" -ForegroundColor Gray
    Write-Host ""
    
}
catch {
    Write-CustomError "Script failed: $_"
    exit 1
}
