function Test-PawdayOwnedProcess($Entry){
 $proc=Get-Process -Id $Entry.id -ErrorAction SilentlyContinue
 if(-not $proc){return $false}
 try{return $proc.StartTime.ToUniversalTime().Ticks -eq ([DateTimeOffset]$Entry.started_at).UtcTicks}catch{return $false}
}
function Get-PawdayStartDisposition($Identity,[bool]$Healthy,[string]$Root){
 if(-not $Identity){return 'NEW'}
 if($Identity.product -ne 'PawdayV1' -or $Identity.root -ne $Root){return 'CONFLICT'}
 if($Healthy){return 'RUNNING'}
 return 'RECOVER'
}
function Start-PawdayDockerEngine{
 if(-not(Get-Command docker -ErrorAction SilentlyContinue)){throw 'Docker Desktop is required. Install it before starting PawdayV1.'}
 try{& docker info --format '{{.ServerVersion}}' *> $null;if($LASTEXITCODE -eq 0){return}}catch{}
 $exe=Join-Path $env:ProgramFiles 'Docker/Docker/Docker Desktop.exe'
 if(-not(Test-Path -LiteralPath $exe)){throw 'Docker Desktop is required. Install it before starting PawdayV1.'}
 Write-Host 'Waiting for Docker Desktop to start...'
 Start-Process -FilePath $exe -WindowStyle Hidden
 for($attempt=0;$attempt -lt 60;$attempt++){
  Start-Sleep -Seconds 2
  try{& docker info --format '{{.ServerVersion}}' *> $null;if($LASTEXITCODE -eq 0){return}}catch{}
 }
 throw 'Docker engine did not become ready. Restart Docker Desktop and retry. Pawday data was not deleted.'
}
function Get-PawdayInfrastructurePorts([string]$Project,[string]$ComposeFile){
 $ports=@{}
 $ids=@(& docker compose -p $Project -f $ComposeFile ps -q)
 if($LASTEXITCODE -ne 0){throw 'Cannot inspect the dedicated Pawday containers.'}
 foreach($container in $ids){
  $items=& docker inspect $container | ConvertFrom-Json
  if($LASTEXITCODE -ne 0){throw 'Cannot verify infrastructure ownership.'}
  foreach($item in $items){
   if($item.Config.Labels.'com.docker.compose.project' -ne $Project){throw 'Foreign infrastructure ownership.'}
   foreach($mapping in $item.NetworkSettings.Ports.PSObject.Properties){
    foreach($binding in $mapping.Value){
     if($binding.HostIp -eq '127.0.0.1'){$ports[[int]$binding.HostPort]=$true}
    }
   }
  }
 }
 return $ports
}
function Set-PawdayRabbitHostname([string]$RoundRoot,[string]$Project){
 $file=Join-Path $RoundRoot 'rabbitmq-hostname.txt'
 if(Test-Path -LiteralPath $file){$name=[IO.File]::ReadAllText($file).Trim()}
 else{
  $engineReady=$false
  try{& docker info --format '{{.ServerVersion}}' *> $null;$engineReady=$LASTEXITCODE -eq 0}catch{}
  if(-not $engineReady){throw 'Docker must be ready before the legacy RabbitMQ identity can be verified.'}
  $items=$null
  try{$items=& docker inspect ($Project+'-rabbitmq-1') 2>$null | ConvertFrom-Json}catch{}
  if($items){
   $item=@($items)[0]
   if($item.Config.Labels.'com.docker.compose.project' -ne $Project){throw 'Cannot migrate a foreign RabbitMQ identity.'}
   $name=$item.Config.Hostname
  }else{
   $legacyVolume=$null
   try{$legacyVolume=& docker volume inspect ($Project+'_rabbitmq-data') 2>$null}catch{}
   if($legacyVolume){throw 'Legacy RabbitMQ data exists without a verified node identity. Retain its data and restore the original node before retrying.'}
   $name='pawday-pilot-rabbitmq'
  }
  if($name -notmatch '^[a-zA-Z0-9][a-zA-Z0-9.-]{0,62}$'){throw 'Invalid RabbitMQ node identity.'}
  [IO.File]::WriteAllText($file,$name,[Text.Encoding]::ASCII)
 }
 if($name -notmatch '^[a-zA-Z0-9][a-zA-Z0-9.-]{0,62}$'){throw 'Invalid RabbitMQ node identity.'}
 [Environment]::SetEnvironmentVariable('PILOT_MQ_HOSTNAME',$name,'Process')
}
