$ErrorActionPreference = "Continue"

Set-Location "$PSScriptRoot"

$env:PORT = "4012"
$env:OWNER_PHONE = "7042773732"
$env:OWNER_EMAIL = "owner@example.com"
$env:TWILIO_SID = "ACxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
$env:TWILIO_AUTH = "invalid_token"
$env:TWILIO_NUMBER = "+17045551234"
$env:SENDGRID_KEY = "SG.invalid"
$env:SENDGRID_FROM = "noreply@example.com"
$env:PUBLIC_RECORDS_WEBHOOK_SECRET = "testsecret"

$server = Start-Process -FilePath node -ArgumentList "src/index.js" -PassThru
Start-Sleep -Seconds 3

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

function Run-Test {
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

try {
  Run-Test -Name "health" -Method "GET" -Url "http://127.0.0.1:4012/health"

  Run-Test -Name "notify invalid channel" -Method "POST" -Url "http://127.0.0.1:4012/internal/owner-notify" -ContentType "application/json" -Body '{"subject":"s","message":"m","channels":["push"]}'

  Run-Test -Name "notify missing fields" -Method "POST" -Url "http://127.0.0.1:4012/internal/owner-notify" -ContentType "application/json" -Body '{"subject":"","message":"","channels":[]}'

  Run-Test -Name "twilio unauthorized sender" -Method "POST" -Url "http://127.0.0.1:4012/webhooks/twilio/sms" -ContentType "application/x-www-form-urlencoded" -Body "From=%2B17040000000&Body=CALL&MessageSid=SM1"

  Run-Test -Name "twilio authorized INFO" -Method "POST" -Url "http://127.0.0.1:4012/webhooks/twilio/sms" -ContentType "application/x-www-form-urlencoded" -Body "From=%2B17042773732&Body=INFO&MessageSid=SM2"

  Run-Test -Name "twilio unknown command" -Method "POST" -Url "http://127.0.0.1:4012/webhooks/twilio/sms" -ContentType "application/x-www-form-urlencoded" -Body "From=%2B17042773732&Body=HELLO&MessageSid=SM3"

  Run-Test -Name "high-priority valid" -Method "POST" -Url "http://127.0.0.1:4012/internal/high-priority-event" -ContentType "application/json" -Body '{"name":"Alex","score":88}'

  Run-Test -Name "high-priority invalid score" -Method "POST" -Url "http://127.0.0.1:4012/internal/high-priority-event" -ContentType "application/json" -Body '{"name":"Alex","score":"bad"}'

  Run-Test -Name "public-records wrong secret" -Method "POST" -Url "http://127.0.0.1:4012/webhooks/public-records/lead" -ContentType "application/json" -Body '{"name":"Dana","email":"dana@example.com","score":90}' -Headers @{ "x-webhook-secret" = "wrong" }

  Run-Test -Name "public-records missing name" -Method "POST" -Url "http://127.0.0.1:4012/webhooks/public-records/lead" -ContentType "application/json" -Body '{"email":"dana@example.com","score":90}' -Headers @{ "x-webhook-secret" = "testsecret" }

  Run-Test -Name "public-records missing contact" -Method "POST" -Url "http://127.0.0.1:4012/webhooks/public-records/lead" -ContentType "application/json" -Body '{"name":"Dana","score":90}' -Headers @{ "x-webhook-secret" = "testsecret" }

  Run-Test -Name "public-records score79" -Method "POST" -Url "http://127.0.0.1:4012/webhooks/public-records/lead" -ContentType "application/json" -Body '{"name":"Dana","email":"dana@example.com","score":79}' -Headers @{ "x-webhook-secret" = "testsecret" }

  Run-Test -Name "public-records score80" -Method "POST" -Url "http://127.0.0.1:4012/webhooks/public-records/lead" -ContentType "application/json" -Body '{"name":"Dana","email":"dana@example.com","score":80}' -Headers @{ "x-webhook-secret" = "testsecret" }

  Run-Test -Name "notify sms+email provider fail expected" -Method "POST" -Url "http://127.0.0.1:4012/internal/owner-notify" -ContentType "application/json" -Body '{"subject":"Hot Lead","message":"Lead Dana","channels":["sms","email"]}'

  $results | ConvertTo-Json -Depth 6
}
finally {
  if ($server -and !$server.HasExited) {
    Stop-Process -Id $server.Id -Force
  }
}
