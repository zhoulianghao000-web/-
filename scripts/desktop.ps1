param([ValidateSet('Start','Stop','Status','Accounts')][string]$Action='Start',[switch]$NoBrowser)
$ErrorActionPreference='Stop'
$taskRoot=[IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$hash=[Security.Cryptography.SHA256]::Create()
try{$rootId=([BitConverter]::ToString($hash.ComputeHash([Text.Encoding]::UTF8.GetBytes($taskRoot.ToLowerInvariant())))).Replace('-','').Substring(0,12).ToLowerInvariant()}finally{$hash.Dispose()}
$round='desktop-'+$rootId;$roundRoot=Join-Path $taskRoot ('.pilot/'+$round);$config=Join-Path $roundRoot 'config.env';$stateFile=Join-Path $roundRoot 'desktop-processes.json';$project='pawday-pilot-'+$round
$node=Join-Path $taskRoot 'runtime/node/node.exe';$java=Join-Path $taskRoot 'runtime/java/bin/java.exe';$jar=Join-Path $taskRoot 'release/pawday-backend.jar'
function Get-LocalIdentity([int]$Port){try{Invoke-RestMethod -Uri "http://127.0.0.1:$Port/desktop-identity" -TimeoutSec 2}catch{return $null}}
function Owns-Process($Entry){
 $proc=Get-Process -Id $Entry.id -ErrorAction SilentlyContinue
 if(-not $proc){return $false}
 try{return $proc.StartTime.ToUniversalTime().ToString('o') -eq $Entry.started_at}catch{return $false}
}
function Read-Config{
 if(-not(Test-Path -LiteralPath $config)){throw 'Initialize this local environment first.'}
 $values=@{};foreach($line in [IO.File]::ReadAllLines($config)){$pair=$line.Split(@('='),2,[StringSplitOptions]::None);if($pair.Length -ne 2 -or $pair[0] -notmatch '^[A-Z][A-Z0-9_]*$'){throw 'Invalid private configuration'};$values[$pair[0]]=$pair[1]};return $values
}
if($Action -eq 'Accounts'){
 $values=Read-Config
 Add-Type -AssemblyName System.Windows.Forms
 $form=New-Object Windows.Forms.Form;$form.Text='PawdayV1 - Private LOCAL test accounts';$form.Width=800;$form.Height=540;$form.StartPosition='CenterScreen'
 $text=New-Object Windows.Forms.TextBox;$text.Multiline=$true;$text.ReadOnly=$true;$text.ScrollBars='Both';$text.Dock='Fill';$text.Font=New-Object Drawing.Font('Consolas',11)
 $refresh=New-Object Windows.Forms.Button;$refresh.Text='Refresh local SMS codes';$refresh.Dock='Bottom';$refresh.Height=40
 $update={
  $lines=@('SIMULATED LOCAL ENVIRONMENT ONLY - do not share screenshots.', '', 'Merchant: local-staff-a / local-staff-b', ('Password: '+$values.PAWDAY_DEMO_MERCHANT_PASSWORD), '', 'Admin: local-admin', ('Password: '+$values.PAWDAY_DEMO_ADMIN_PASSWORD), '', 'Consumers: +999000000001 ... +999000000020', 'Request a code in the app, then refresh this local window.', '', 'Latest LOCAL simulated SMS:')
  $sms=Join-Path $roundRoot 'sms';if(Test-Path -LiteralPath $sms){Get-ChildItem -LiteralPath $sms -Filter '*.txt' | Sort-Object LastWriteTime -Descending | Select-Object -First 5 | ForEach-Object {$parts=[IO.File]::ReadAllLines($_.FullName);if($parts.Length -ge 2){$lines+=($parts[0]+'   '+$parts[1]+'   '+$_.LastWriteTime.ToString('HH:mm:ss'))}}}
  $text.Lines=$lines
 }.GetNewClosure()
 $refresh.Add_Click($update);$form.Controls.Add($text);$form.Controls.Add($refresh);& $update;[void]$form.ShowDialog();return
}
if($Action -eq 'Status'){
 foreach($port in @(4172,4273,4174,4175)){$id=Get-LocalIdentity $port;Write-Host "$port : $($id.site) $($id.mode)"};return
}
if($Action -eq 'Stop'){
 if(Test-Path -LiteralPath $stateFile){
  $state=Get-Content -Raw -LiteralPath $stateFile | ConvertFrom-Json
  if($state.root -ne $taskRoot){throw 'Process ownership does not match this delivery'}
  foreach($entry in $state.processes){if(Owns-Process $entry){Stop-Process -Id $entry.id -ErrorAction Stop}}
  Remove-Item -LiteralPath $stateFile
 }
 if(Test-Path -LiteralPath $config){& (Join-Path $PSScriptRoot 'pilot-environment.ps1') -Round $round -Action Stop}
 Write-Host 'PawdayV1 stopped. Database, media and credentials are retained.';return
}
foreach($file in @($node,$java,$jar,(Join-Path $taskRoot 'release/desktop-manifest.json'))){if(-not(Test-Path -LiteralPath $file)){throw 'Incomplete delivery. Extract the complete Development package.'}}
$existing=Get-LocalIdentity 4172
if($existing -and $existing.product -eq 'PawdayV1' -and $existing.root -eq $taskRoot){
 $status=Invoke-RestMethod -Uri 'http://127.0.0.1:4172/desktop-status' -TimeoutSec 5
 if(-not $status.healthy){throw 'Local processes exist but backend is unhealthy. Stop this delivery, check logs, then start again.'}
 if(-not $NoBrowser){Start-Process 'http://127.0.0.1:4172'};Write-Host 'PawdayV1 is already running.';return
}
foreach($port in @(8086,4172,4273,4174,4175,5546,6386,5676,9206,15676)){
 $listeners=Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue
 if($listeners){throw "Local port $port is occupied. Stop only its owning environment before retrying."}
}
& docker info --format '{{.ServerVersion}}' *> $null
if($LASTEXITCODE -ne 0){throw 'Start Docker Desktop and wait for its engine before launching PawdayV1.'}
if(-not(Test-Path -LiteralPath $config)){& (Join-Path $PSScriptRoot 'pilot-environment.ps1') -Round $round -Action Init}
$values=Read-Config
# Do not inherit credentials or provider addresses from another deployment.
Get-ChildItem Env: | Where-Object Name -match '^(PAWDAY_|SPRING_|REDIS_|RABBITMQ_|OPENSEARCH_|SERVER_|PILOT_)' | ForEach-Object {[Environment]::SetEnvironmentVariable($_.Name,$null,'Process')}
foreach($key in $values.Keys){[Environment]::SetEnvironmentVariable($key,$values[$key],'Process')}
$env:SPRING_DATASOURCE_URL="jdbc:postgresql://127.0.0.1:5546/$($values.PILOT_DB_NAME)";$env:SPRING_DATASOURCE_PASSWORD=$values.PILOT_DB_PASSWORD;$env:RABBITMQ_PASSWORD=$values.PILOT_MQ_PASSWORD
$processes=@();$ownedInfrastructure=$false
Push-Location $taskRoot
try{
 Write-Host 'Starting dedicated PostgreSQL / Redis / RabbitMQ / OpenSearch...'
 $occupied=& docker compose -p $project -f compose.pilot.yaml ps -q
 if($occupied){throw 'This project already has containers. Use its Stop command before restarting.'}
 $ownedInfrastructure=$true
 & docker compose -p $project -f compose.pilot.yaml up -d --wait --wait-timeout 300
 if($LASTEXITCODE -ne 0){throw 'Infrastructure failed health checks.'}
 Write-Host 'Starting local application...'
 $backend=Start-Process -FilePath $java -ArgumentList @('-jar',('"'+$jar+'"')) -WorkingDirectory $taskRoot -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $roundRoot 'backend.log') -RedirectStandardError (Join-Path $roundRoot 'backend-error.log')
 $processes+=@{id=$backend.Id;started_at=$backend.StartTime.ToUniversalTime().ToString('o')}
 $healthy=$false
 for($attempt=0;$attempt -lt 150;$attempt++){
  if($backend.HasExited){throw 'Backend exited. Check backend.log in this delivery private .pilot round.'}
  try{$health=Invoke-RestMethod -Uri 'http://127.0.0.1:8086/actuator/health' -TimeoutSec 2;if($health.status -eq 'UP'){$healthy=$true;break}}catch{}
  Start-Sleep -Seconds 1
 }
 if(-not $healthy){throw 'Backend health timeout. Check backend.log in this delivery private .pilot round.'}
 $web=Start-Process -FilePath $node -ArgumentList @(('"'+(Join-Path $PSScriptRoot 'desktop-server.mjs')+'"'),('"'+$taskRoot+'"')) -WorkingDirectory $taskRoot -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $roundRoot 'desktop.log') -RedirectStandardError (Join-Path $roundRoot 'desktop-error.log')
 $processes+=@{id=$web.Id;started_at=$web.StartTime.ToUniversalTime().ToString('o')}
 for($attempt=0;$attempt -lt 15;$attempt++){if(Get-LocalIdentity 4172){break};Start-Sleep -Seconds 1}
 foreach($port in @(4172,4273,4174,4175)){$id=Get-LocalIdentity $port;if(-not $id -or $id.root -ne $taskRoot){throw "Desktop service $port failed identity check"}}
 @{root=$taskRoot;processes=$processes} | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $stateFile -Encoding UTF8
 if(-not $NoBrowser){Start-Process 'http://127.0.0.1:4172'}
 Write-Host 'PawdayV1 is ready. http://127.0.0.1:4172'
}catch{
 foreach($entry in $processes){if(Owns-Process $entry){Stop-Process -Id $entry.id -ErrorAction SilentlyContinue}}
 if($ownedInfrastructure){& docker compose -p $project -f compose.pilot.yaml down}
 throw
}finally{Pop-Location}
