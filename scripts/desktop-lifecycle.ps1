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
