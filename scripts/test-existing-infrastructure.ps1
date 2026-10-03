param(
    [Parameter(Mandatory=$true)][int]$RabbitPort,
    [Parameter(Mandatory=$true)][string]$RabbitUser,
    [Parameter(Mandatory=$true)][string]$RabbitPassword,
    [Parameter(Mandatory=$true)][int]$RedisPort,
    [Parameter(Mandatory=$true)][string]$OpenSearchUrl,
    [string]$RabbitHost='127.0.0.1',
    [string]$RedisHost='127.0.0.1',
    [string]$RabbitMqCtl,
    [string]$RabbitContainer
)
$ErrorActionPreference='Stop'
$taskRoot=Split-Path -Parent $PSScriptRoot
$taskCluster=Invoke-RestMethod -Uri ($OpenSearchUrl.TrimEnd('/')+'/_cluster/health') -TimeoutSec 5
if($taskCluster.cluster_name -ne 'pawday-m23-it'){throw 'Tests require a dedicated pawday-m23-it OpenSearch cluster and mutate only its Pawday test indexes.'}
if(-not $RabbitMqCtl -and -not $RabbitContainer){throw 'A native rabbitmqctl path or isolated Docker container is required for the real stop_app/start_app gate.'}
$env:PAWDAY_IT_RABBIT_HOST=$RabbitHost
$env:PAWDAY_IT_RABBIT_PORT=$RabbitPort.ToString()
$env:PAWDAY_IT_RABBIT_USER=$RabbitUser
$env:PAWDAY_IT_RABBIT_PASSWORD=$RabbitPassword
$env:PAWDAY_IT_REDIS_HOST=$RedisHost
$env:PAWDAY_IT_REDIS_PORT=$RedisPort.ToString()
$env:PAWDAY_IT_OPENSEARCH_URL=$OpenSearchUrl
if($RabbitMqCtl){$env:PAWDAY_RABBITMQ_CTL=$RabbitMqCtl}
if($RabbitContainer){$env:PAWDAY_IT_RABBIT_CONTAINER=$RabbitContainer}
Push-Location $taskRoot
try {& mvn -B -ntp -f backend/pom.xml -Pinfrastructure-it verify;if($LASTEXITCODE -ne 0){throw 'Mandatory real infrastructure gate failed'}}finally{Pop-Location}
