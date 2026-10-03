$ErrorActionPreference='Stop'
$taskRoot=Split-Path -Parent $PSScriptRoot
$taskComposePath=Join-Path $taskRoot 'compose.integration.yaml'
$taskProject='pawday-m23-it'
$taskExisting = & docker compose -p $taskProject -f $taskComposePath ps -aq
if($LASTEXITCODE -ne 0){throw 'Docker Compose unavailable; real infrastructure tests are mandatory'}
if($taskExisting){throw 'An isolated M2.3 test project already exists; inspect it before rerunning'}
$env:PAWDAY_IT_RABBIT_HOST='127.0.0.1'
$env:PAWDAY_IT_RABBIT_PORT='5675'
$env:PAWDAY_IT_RABBIT_USER='pawday_it'
$env:PAWDAY_IT_RABBIT_PASSWORD='TEST_ONLY_m22_broker'
$env:PAWDAY_IT_RABBIT_CONTAINER='pawday-m23-it-rabbitmq-1'
$env:PAWDAY_IT_REDIS_HOST='127.0.0.1'
$env:PAWDAY_IT_REDIS_PORT='6385'
$env:PAWDAY_IT_OPENSEARCH_URL='http://127.0.0.1:9205'
Push-Location $taskRoot
try {
    & docker compose -p $taskProject -f $taskComposePath up -d --wait --wait-timeout 300
    if($LASTEXITCODE -ne 0){throw 'Real four-service readiness failed; no mock fallback allowed'}
    & mvn -B -ntp -f backend/pom.xml -Pinfrastructure-it verify
    if($LASTEXITCODE -ne 0){throw 'Storage / real search / Redis / RabbitMQ mandatory gate failed'}
} finally {
    & docker compose -p $taskProject -f $taskComposePath logs --no-color
    & docker compose -p $taskProject -f $taskComposePath down
    Pop-Location
}
