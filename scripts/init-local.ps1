$ErrorActionPreference = 'Stop'
$taskRoot = Split-Path -Parent $PSScriptRoot
$envPath = Join-Path $taskRoot '.env.local'
if ((Test-Path -LiteralPath $envPath)) { throw 'Local secrets already exist; preserve them. Use an empty local database when creating new secrets.' }
function New-RandomBytes([int]$count) { $bytes = New-Object byte[] $count; $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create(); try { $rng.GetBytes($bytes) } finally { $rng.Dispose() }; return ,$bytes }
$secret=[Convert]::ToBase64String((New-RandomBytes 32))
$merchantPassword=[Convert]::ToBase64String((New-RandomBytes 24)); $adminPassword=[Convert]::ToBase64String((New-RandomBytes 24))
$lines=@('SPRING_PROFILES_ACTIVE=local','PAWDAY_DEMO_ENABLED=true','PAWDAY_LOCAL_SMS_ENABLED=true',"PAWDAY_AUTH_SECRET=$secret", "PAWDAY_DEMO_MERCHANT_PASSWORD=$merchantPassword", "PAWDAY_DEMO_ADMIN_PASSWORD=$adminPassword")
[IO.File]::WriteAllLines($envPath,$lines,[Text.UTF8Encoding]::new($false))
Write-Host 'Created ignored local configuration. No secrets were printed.'
