$ErrorActionPreference='Stop'
$taskRoot=Split-Path -Parent $PSScriptRoot
$container='pawday-m22-it'
& docker inspect $container *> $null
if($LASTEXITCODE -eq 0){throw 'The isolated test container already exists. Inspect/remove it before starting this test run.'}
$env:PAWDAY_IT_RABBIT_CONTAINER=$container
$env:PAWDAY_IT_RABBIT_HOST='127.0.0.1'
$env:PAWDAY_IT_RABBIT_PORT='5675'
$env:PAWDAY_IT_RABBIT_USER='pawday_it'
$env:PAWDAY_IT_RABBIT_PASSWORD='TEST_ONLY_m22_broker'
& docker run -d --name $container -p 127.0.0.1:5675:5672 -e RABBITMQ_DEFAULT_USER=pawday_it -e RABBITMQ_DEFAULT_PASS=TEST_ONLY_m22_broker rabbitmq:4.3.6-management
if($LASTEXITCODE -ne 0){throw 'Real RabbitMQ test broker failed to start'}
try {
    $ready=$false
    for($attempt=0;$attempt -lt 30;$attempt++){
        & docker exec $container rabbitmq-diagnostics -q check_running *> $null
        if($LASTEXITCODE -eq 0){$ready=$true;break};Start-Sleep -Seconds 2
    }
    if(-not $ready){throw 'Real broker readiness failed; MQ tests cannot be skipped'}
    Push-Location $taskRoot
    try {& mvn -B -ntp -f backend/pom.xml -Prabbit-it verify;if($LASTEXITCODE -ne 0){throw 'M2.2 mandatory real RabbitMQ gate failed'}} finally {Pop-Location}
} finally {
    & docker stop $container | Out-Null
    & docker rm $container | Out-Null
}
