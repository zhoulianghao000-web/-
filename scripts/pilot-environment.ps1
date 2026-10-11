param([Parameter(Mandatory=$true)][ValidatePattern('^[a-z][a-z0-9-]{0,30}$')][string]$Round,[ValidateSet('Init','Start','Pause','Resume','Stop')][string]$Action='Start')
$ErrorActionPreference='Stop'
$taskRoot=Split-Path -Parent $PSScriptRoot
$base=[IO.Path]::GetFullPath((Join-Path $taskRoot '.pilot'))
$roundRoot=[IO.Path]::GetFullPath((Join-Path $base $Round))
if(-not $roundRoot.StartsWith($base+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){throw 'Invalid dedicated pilot root'}
$config=Join-Path $roundRoot 'config.env';$project="pawday-pilot-$Round"
if($Action -eq 'Init'){
 if(Test-Path -LiteralPath $roundRoot){throw 'Round exists; preserve its credentials. Choose a new round name.'}
 [void][IO.Directory]::CreateDirectory($roundRoot)
 function New-PilotSecret([int]$Count){$bytes=New-Object byte[] $Count;[Security.Cryptography.RandomNumberGenerator]::Fill($bytes);return [Convert]::ToBase64String($bytes)}
 $lines=@('SPRING_PROFILES_ACTIVE=local,pilot','PAWDAY_DEPLOYMENT_MODE=pilot','PAWDAY_DEMO_ENABLED=true','PAWDAY_LOCAL_SMS_ENABLED=true',"PAWDAY_PILOT_ROOT=$roundRoot",'SERVER_ADDRESS=127.0.0.1','SERVER_PORT=8086',"PILOT_DB_NAME=pawday_pilot_$($Round.Replace('-','_'))",'SPRING_DATASOURCE_USERNAME=pawday_pilot','REDIS_HOST=127.0.0.1','REDIS_PORT=6386','RABBITMQ_HOST=127.0.0.1','RABBITMQ_PORT=5676','RABBITMQ_USER=pawday_pilot','OPENSEARCH_URL=http://127.0.0.1:9206',"PAWDAY_AUTH_SECRET=$(New-PilotSecret 32)","PAWDAY_DEMO_MERCHANT_PASSWORD=$(New-PilotSecret 24)","PAWDAY_DEMO_ADMIN_PASSWORD=$(New-PilotSecret 24)","PAWDAY_DEMO_ADMIN_TOTP_BASE64=$(New-PilotSecret 20)","PILOT_DB_PASSWORD=$(New-PilotSecret 24)","PILOT_MQ_PASSWORD=$(New-PilotSecret 24)")
 [IO.File]::WriteAllLines($config,$lines,[Text.UTF8Encoding]::new($false))
 Write-Host 'Created private ignored pilot configuration. No secrets printed.';return
}
if(-not(Test-Path -LiteralPath $config)){throw 'Initialize this round first.'}
if($Action -eq 'Pause'){[IO.File]::WriteAllText((Join-Path $roundRoot 'PAUSED'),'operator pause');return}
if($Action -eq 'Resume'){Remove-Item -LiteralPath (Join-Path $roundRoot 'PAUSED') -ErrorAction SilentlyContinue;return}
foreach($line in [IO.File]::ReadAllLines($config)){$pair=$line.Split(@('='),2,[StringSplitOptions]::None);if($pair.Length -ne 2 -or $pair[0] -notmatch '^[A-Z][A-Z0-9_]*$'){throw 'Invalid pilot configuration'};[Environment]::SetEnvironmentVariable($pair[0],$pair[1],'Process')}
$env:SPRING_DATASOURCE_URL="jdbc:postgresql://127.0.0.1:5546/$env:PILOT_DB_NAME"
$env:SPRING_DATASOURCE_PASSWORD=$env:PILOT_DB_PASSWORD;$env:RABBITMQ_PASSWORD=$env:PILOT_MQ_PASSWORD
Push-Location $taskRoot
try {
 if($Action -eq 'Stop'){& docker compose -p $project -f compose.pilot.yaml down;if($LASTEXITCODE -ne 0){throw 'Pilot infrastructure stop failed'};return}
 & docker compose -p $project -f compose.pilot.yaml up -d --wait --wait-timeout 300
 if($LASTEXITCODE -ne 0){throw 'Pilot infrastructure startup failed'}
 $jar=Join-Path $taskRoot 'release/pawday-backend.jar'
 if(-not(Test-Path -LiteralPath $jar)){$jar=Join-Path $taskRoot 'backend/target/pawday-backend-0.6.6-SNAPSHOT.jar'}
 if(-not(Test-Path -LiteralPath $jar)){throw 'Build or obtain this stage JAR first.'}
 & java -jar $jar
 if($LASTEXITCODE -ne 0){throw 'Pilot application failed'}
} finally {Pop-Location}
