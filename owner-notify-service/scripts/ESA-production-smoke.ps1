$ErrorActionPreference = "Continue"

Set-Location "$PSScriptRoot\.."

$envRequired = @(
  "PORT",
  "OWNER_PHONE",
  "OWNER_EMAIL",
  "PUBLIC_RECORDS_WEBHOOK_SECRET"
)

$missing = @()
foreach ($name in $envRequired) {
  $value = [Environment]::GetEnvironmentVariable($name)
  if ([string]::IsNullOrWhiteSpace($value)) {
    $missing += $name
  }
}

if ($missing.Count -gt 0) {
  Write-Host "Missing required environment variables for smoke test:" -ForegroundColor Yellow
  $missing | ForEach-Object { Write-Host " - $_" -ForegroundColor Yellow }
  Write-Host "Result: FAIL (env validation)" -ForegroundColor Red
  exit 1
}

$results = @()

function Add-Result {
  param(
    [string]$Name,
    [int]$Status,
    [string]$Body
  )
  $global:results += [PSCustomObject]@{
    test = $Name
    status = $Status
    body = $Body
  }
}

function Invoke-SmokeRequest {
  param(
    [string]$Name,
    [string]$Method,
    [string]$Url,
    [string]$ContentType,
    [string]$Body,
    [hashtable]$Headers
  )

  try {
    if ($Headers -and $ContentType) {
      $resp = Invoke-WebRequest -Method $Method -Uri $Url -Headers $Headers -ContentType $ContentType -Body $Body -UseBasicParsing
    } elseif ($Headers) {
      $resp = Invoke-WebRequest -Method $Method -Uri $Url -Headers $Headers -UseBasicParsing
    } elseif ($ContentType) {
      $resp = Invoke-WebRequest -Method $Method -Uri $Url -ContentType $ContentType -Body $Body -UseBasicParsing
    } else {
      $resp = Invoke-WebRequest -Method $Method -Uri $Url -UseBasicParsing
    }

    Add-Result -Name $Name -Status ([int]$resp.StatusCode) -Body ([string]$resp.Content)
  } catch {
    if ($_.Exception.Response) {
      $response = $_.Exception.Response
      $statusCode = [int]$response.StatusCode
      $reader = New-Object IO.StreamReader($response.GetResponseStream())
      $content = $reader.ReadToEnd()
      Add-Result -Name $Name -Status $statusCode -Body $content
    } else {
      Add-Result -Name $Name -Status 0 -Body ("ERROR: " + $_.Exception.Message)
    }
  }
}

$port = [int]$env:PORT
$base = "http://127.0.0.1:$port"

$server = Start-Process -FilePath node -ArgumentList "src/index.js" -PassThru

$healthy = $false
for ($i = 0; $i -lt 20; $i++) {
  Start-Sleep -Milliseconds 500
  try {
    $healthResp = Invoke-WebRequest -Method GET -Uri "$base/health" -UseBasicParsing
    if ([int]$healthResp.StatusCode -eq 200) {
      $healthy = $true
      break
    }
  } catch {
    # wait for app startup
  }
}

try {
  if (-not $healthy) {
    Add-Result -Name "health readiness" -Status 0 -Body "Service did not become healthy in time."
    $results | ConvertTo-Json -Depth 6
    exit 1
  }

  Invoke-SmokeRequest -Name "health" -Method "GET" -Url "$base/health"

  Invoke-SmokeRequest `
    -Name "owner sms command INFO" `
    -Method "POST" `
    -Url "$base/webhooks/twilio/sms" `
    -ContentType "application/x-www-form-urlencoded" `
    -Body ("From=%2B1{0}&Body=INFO&MessageSid=SMOKE1" -f $env:OWNER_PHONE)

  Invoke-SmokeRequest `
    -Name "public-records valid lead (score 80)" `
    -Method "POST" `
    -Url "$base/webhooks/public-records/lead" `
    -ContentType "application/json" `
    -Body '{"name":"Smoke Lead","email":"smoke.lead@example.com","score":80}' `
    -Headers @{ "x-webhook-secret" = $env:PUBLIC_RECORDS_WEBHOOK_SECRET }

  $results | ConvertTo-Json -Depth 6

  $hasFailure = $false
  foreach ($r in $results) {
    if ($r.status -lt 200 -or $r.status -gt 299) {
      $hasFailure = $true
      break
    }
  }

  if ($hasFailure) {
    Write-Host "Result: FAIL (smoke)" -ForegroundColor Red
    exit 1
  }

  Write-Host "Result: PASS (smoke)" -ForegroundColor Green
  exit 0
}
finally {
  if ($server -and -not $server.HasExited) {
    Stop-Process -Id $server.Id -Force
  }
}
