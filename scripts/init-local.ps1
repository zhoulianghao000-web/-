$ErrorActionPreference = 'Stop'
$taskRoot = Split-Path -Parent $PSScriptRoot
$envPath = Join-Path $taskRoot '.env.local'
$authPath = Join-Path $taskRoot '.local-authenticator.txt'
if ((Test-Path -LiteralPath $envPath) -or (Test-Path -LiteralPath $authPath)) { throw 'Local secrets already exist; preserve them. Use an empty local database when creating new secrets.' }
function New-RandomBytes([int]$count) { $bytes = New-Object byte[] $count; $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create(); try { $rng.GetBytes($bytes) } finally { $rng.Dispose() }; return ,$bytes }
function To-Base32([byte[]]$bytes) {
    $alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567'; $builder = New-Object System.Text.StringBuilder; $buffer=0; $bits=0
    foreach ($byte in $bytes) { $buffer=($buffer -shl 8) -bor $byte; $bits+=8; while ($bits -ge 5) { $bits-=5; [void]$builder.Append($alphabet[($buffer -shr $bits) -band 31]) }; $buffer=$buffer -band ((1 -shl $bits)-1) }
    if ($bits -gt 0) { [void]$builder.Append($alphabet[($buffer -shl (5-$bits)) -band 31]) }; return $builder.ToString()
}
$secret=[Convert]::ToBase64String((New-RandomBytes 32)); $totp=New-RandomBytes 20
$merchantPassword=[Convert]::ToBase64String((New-RandomBytes 24)); $adminPassword=[Convert]::ToBase64String((New-RandomBytes 24))
$lines=@('SPRING_PROFILES_ACTIVE=local','PAWDAY_DEMO_ENABLED=true','PAWDAY_LOCAL_SMS_ENABLED=true',"PAWDAY_AUTH_SECRET=$secret", "PAWDAY_DEMO_MERCHANT_PASSWORD=$merchantPassword", "PAWDAY_DEMO_ADMIN_PASSWORD=$adminPassword", "PAWDAY_DEMO_ADMIN_TOTP_BASE64=$([Convert]::ToBase64String($totp))")
[IO.File]::WriteAllLines($envPath,$lines,[Text.UTF8Encoding]::new($false))
[IO.File]::WriteAllText($authPath,"LOCAL DEMO ONLY`nIssuer: Pawday-local`nAccount: local-admin`nAlgorithm: SHA1, digits: 6, period: 30 seconds`nBase32 secret: $(To-Base32 $totp)`nMerchant login names: local-staff-a / local-staff-b`nAdmin login name: local-admin`nPasswords are in .env.local. Each TOTP time step is one-use; wait for a new code before reverify.`n",[Text.UTF8Encoding]::new($false))
Write-Host 'Created ignored local configuration and authenticator enrollment file. No secrets were printed.'
