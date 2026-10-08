$ErrorActionPreference = 'Stop'
$taskRoot = Split-Path -Parent $PSScriptRoot
$envPath=Join-Path $taskRoot '.env.local'
if (-not (Test-Path -LiteralPath $envPath)) { throw 'Run scripts/init-local.ps1 first.' }
foreach($line in [IO.File]::ReadAllLines($envPath)) {
    if([string]::IsNullOrWhiteSpace($line) -or $line.StartsWith('#')) { continue }
    $pair=$line.Split(@('='),2,[StringSplitOptions]::None)
    if($pair.Length -ne 2 -or $pair[0] -notmatch '^[A-Z][A-Z0-9_]*$') { throw 'Invalid local environment entry' }
    [Environment]::SetEnvironmentVariable($pair[0],$pair[1],'Process')
}
Push-Location $taskRoot
try {
    & docker compose up -d --wait --wait-timeout 300
    if($LASTEXITCODE -ne 0) { throw 'Infrastructure startup failed' }
    $jarPath=Join-Path $taskRoot 'release/pawday-backend.jar'
    if(Test-Path -LiteralPath $jarPath) { & java -jar $jarPath }
    else { & mvn -f backend/pom.xml spring-boot:run }
    if($LASTEXITCODE -ne 0) { throw 'Backend startup failed' }
} finally { Pop-Location }
