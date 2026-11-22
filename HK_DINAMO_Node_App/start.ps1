# UTF-8 PowerShell launcher for the HK Dinamo Node.js application.
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)
$OutputEncoding = [Console]::OutputEncoding

try {
    Set-Location -LiteralPath $PSScriptRoot
    Write-Host '============================================================' -ForegroundColor Cyan
    Write-Host '  Запуск веб-приложения ХК Динамо-Минск' -ForegroundColor Cyan
    Write-Host '============================================================' -ForegroundColor Cyan

    if (-not (Test-Path -LiteralPath (Join-Path $PSScriptRoot '.env'))) {
        Write-Host 'Не найден файл .env.' -ForegroundColor Yellow
        Write-Host 'Скопируйте .env.example в .env и заполните параметры Oracle.'
        Write-Host 'Команды для PowerShell:'
        Write-Host '  Copy-Item .env.example .env'
        Write-Host '  notepad .env'
        exit 1
    }

    $node = Get-Command node.exe -ErrorAction SilentlyContinue
    $npm = Get-Command npm.cmd -ErrorAction SilentlyContinue
    if (-not $node -or -not $npm) {
        Write-Host 'Node.js не найден. Установите Node.js 22 или новее и перезапустите этот файл.' -ForegroundColor Red
        Write-Host 'Официальный сайт: https://nodejs.org/'
        exit 1
    }

    $nodeVersionText = (& node.exe --version 2>&1 | Out-String).Trim()
    Write-Host "Node.js: $nodeVersionText"
    if ($nodeVersionText -notmatch '^v(\d+)\.' -or [int]$Matches[1] -lt 22) {
        Write-Host 'Требуется Node.js версии 22 или новее.' -ForegroundColor Red
        exit 1
    }

    if (-not (Test-Path -LiteralPath (Join-Path $PSScriptRoot 'node_modules'))) {
        Write-Host 'Устанавливаю зависимости Node.js...' -ForegroundColor Yellow
        & npm.cmd install
        if ($LASTEXITCODE -ne 0) { throw "npm install завершился с кодом $LASTEXITCODE" }
    }

    Write-Host 'Проверяю синтаксис JavaScript...' -ForegroundColor Yellow
    & npm.cmd run check
    if ($LASTEXITCODE -ne 0) { throw "Проверка JavaScript завершилась с кодом $LASTEXITCODE" }

    Write-Host ''
    Write-Host 'Запускаю веб-сервер. Для остановки нажмите Ctrl+C.' -ForegroundColor Green
    Write-Host 'После запуска откройте: http://localhost:3000'
    & npm.cmd start
    if ($LASTEXITCODE -ne 0) { throw "Веб-сервер завершился с кодом $LASTEXITCODE" }
}
catch {
    Write-Host ''
    Write-Host ('ОШИБКА: ' + $_.Exception.Message) -ForegroundColor Red
    Write-Host 'Проверьте .env, подключение Oracle и сообщения выше.' -ForegroundColor Yellow
    exit 1
}
