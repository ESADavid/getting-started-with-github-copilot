$ErrorActionPreference = "Continue"

Set-Location "$PSScriptRoot\.."

$required = @(
  "TWILIO_SID",
  "TWILIO_AUTH",
  "TWILIO_NUMBER",
  "SENDGRID_KEY",
  "SENDGRID_FROM",
  "OWNER_PHONE",
  "OWNER_EMAIL"
)

$missing = @()
foreach ($name in $required) {
  $value = [Environment]::GetEnvironmentVariable($name)
  if ([string]::IsNullOrWhiteSpace($value)) {
    $missing += $name
  }
}

if ($missing.Count -gt 0) {
  Write-Host "Missing required environment variables:" -ForegroundColor Yellow
  $missing | ForEach-Object { Write-Host " - $_" -ForegroundColor Yellow }
  Write-Host "Result: FAIL (env validation)" -ForegroundColor Red
  exit 1
}

function Test-TwilioCredentials {
  param(
    [string]$Sid,
    [string]$Auth
  )

  try {
    $pair = "{0}:{1}" -f $Sid, $Auth
    $bytes = [System.Text.Encoding]::ASCII.GetBytes($pair)
    $encoded = [Convert]::ToBase64String($bytes)
    $headers = @{
      Authorization = "Basic $encoded"
    }

    $url = "https://api.twilio.com/2010-04-01/Accounts/$Sid.json"
    $resp = Invoke-WebRequest -Method GET -Uri $url -Headers $headers -UseBasicParsing -TimeoutSec 20
    return ([int]$resp.StatusCode -eq 200)
  } catch {
    return $false
  }
}

function Test-SendGridCredentials {
  param(
    [string]$ApiKey
  )

  try {
    $headers = @{
      Authorization = "Bearer $ApiKey"
      "Content-Type" = "application/json"
    }

    $url = "https://api.sendgrid.com/v3/user/account"
    $resp = Invoke-WebRequest -Method GET -Uri $url -Headers $headers -UseBasicParsing -TimeoutSec 20
    return ([int]$resp.StatusCode -eq 200)
  } catch {
    return $false
  }
}

$twilioOk = Test-TwilioCredentials -Sid $env:TWILIO_SID -Auth $env:TWILIO_AUTH
$sendgridOk = Test-SendGridCredentials -ApiKey $env:SENDGRID_KEY

Write-Host "Credential validation summary:"
Write-Host (" - Twilio:   " + ($(if ($twilioOk) { "PASS" } else { "FAIL" })))
Write-Host (" - SendGrid: " + ($(if ($sendgridOk) { "PASS" } else { "FAIL" })))

if (-not $twilioOk -or -not $sendgridOk) {
  Write-Host "Result: FAIL (provider validation)" -ForegroundColor Red
  exit 1
}

Write-Host "Result: PASS (provider credentials validated)" -ForegroundColor Green
exit 0
