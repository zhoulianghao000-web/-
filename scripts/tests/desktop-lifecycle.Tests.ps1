$ErrorActionPreference='Stop'
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'desktop-lifecycle.ps1')
$count=0
function Assert-Pawday([bool]$Condition,[string]$Name){if(-not $Condition){throw ('FAIL: '+$Name)};$script:count++;Write-Host ('PASS: '+$Name)}
$root='TEST_ROOT'
Assert-Pawday ((Get-PawdayStartDisposition $null $false $root) -eq 'NEW') 'cold start'
$identity=@{product='PawdayV1';root=$root}
Assert-Pawday ((Get-PawdayStartDisposition $identity $true $root) -eq 'RUNNING') 'healthy repeated start'
Assert-Pawday ((Get-PawdayStartDisposition $identity $false $root) -eq 'RECOVER') 'partial failure recovers'
Assert-Pawday ((Get-PawdayStartDisposition @{product='OTHER';root=$root} $true $root) -eq 'CONFLICT') 'foreign product refused'
Assert-Pawday ((Get-PawdayStartDisposition @{product='PawdayV1';root='FOREIGN_ROOT'} $false $root) -eq 'CONFLICT') 'foreign delivery refused'
$self=Get-Process -Id $PID
$entry=@{id=$PID;started_at=$self.StartTime.ToUniversalTime().ToString('o')}
Assert-Pawday (Test-PawdayOwnedProcess $entry) 'exact process identity'
$fromJson=$entry | ConvertTo-Json | ConvertFrom-Json
Assert-Pawday (Test-PawdayOwnedProcess $fromJson) 'JSON timestamp survives PowerShell version differences'
Assert-Pawday (-not(Test-PawdayOwnedProcess @{id=$PID;started_at=[DateTime]::UtcNow.AddDays(-1)})) 'reused PID cannot be stopped'
Assert-Pawday (-not(Test-PawdayOwnedProcess @{id=$PID;started_at='INVALID'})) 'malformed process record refused'
Write-Host ($count.ToString()+' desktop lifecycle checks passed')
