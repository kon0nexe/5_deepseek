#requires -Version 5.1
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
[Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)
$OutputEncoding = [Console]::OutputEncoding

$Root = $PSScriptRoot
$DbRoot = Join-Path $Root 'HK_DINAMO_Oracle19c'
$AppRoot = Join-Path $Root 'HK_DINAMO_Node_App'
$OutputDir = Join-Path $Root 'Результаты_установки'
$Image = 'container-registry.oracle.com/database/enterprise:19.3.0.0'
$Stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$LogFile = Join-Path $OutputDir "установка_$Stamp.log"
$CredFile = Join-Path $OutputDir "доступы_приложения_$Stamp.txt"
$StageParent = Join-Path $env:TEMP "HK_DINAMO_full_$Stamp"
$NlsLang = 'AMERICAN_AMERICA.AL32UTF8'

New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null

function Write-Log([string]$Text) {
    Add-Content -LiteralPath $LogFile -Value $Text -Encoding UTF8
    Write-Host $Text
}
function New-RandomSafe([int]$Length = 24) {
    $alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz23456789'
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    $bytes = New-Object byte[] $Length
    $rng.GetBytes($bytes)
    $chars = for ($i=0; $i -lt $Length; $i++) { $alphabet[[int]($bytes[$i] % $alphabet.Length)] }
    $rng.Dispose()
    return ('Aa7_' + (-join $chars))
}
function New-Secret([int]$Bytes = 32) {
    $b = New-Object byte[] $Bytes
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    $rng.GetBytes($b); $rng.Dispose()
    return ([System.BitConverter]::ToString($b).Replace('-','').ToLowerInvariant())
}
function Invoke-Docker([string[]]$DockerArgs, [string]$Label) {
    Write-Host "`n$Label" -ForegroundColor Cyan
    & docker @DockerArgs 2>&1 | ForEach-Object {
        $line = [string]$_
        Add-Content -LiteralPath $LogFile -Value $line -Encoding UTF8
        Write-Host $line
    }
    $code = $LASTEXITCODE
    if ($code -ne 0) { throw "$Label завершилось с кодом $code. См. $LogFile" }
}
function Wait-Oracle([string]$Container, [bool]$NewContainer) {
    Write-Host "Проверяю готовность Oracle в контейнере $Container..." -ForegroundColor Cyan
    for ($i=1; $i -le 180; $i++) {
        if ($NewContainer) {
            $text = (& docker logs --tail 300 $Container 2>&1 | Out-String)
            if ($text -match 'DATABASE IS READY TO USE!') { Write-Log 'Oracle готов к работе.'; return }
        } else {
            & docker exec -u oracle -e "NLS_LANG=$NlsLang" $Container bash -lc "printf 'EXIT\n' | sqlplus -s / as sysdba" *> $null
            if ($LASTEXITCODE -eq 0) { Write-Log 'SQL*Plus успешно подключился к Oracle.'; return }
        }
        if (($i % 6) -eq 0) { Write-Host "Ожидание Oracle: попытка $i из 180 (максимум около 30 минут)..." }
        Start-Sleep -Seconds 10
    }
    $tail = & docker logs --tail 100 $Container 2>&1
    $tail | Add-Content -LiteralPath $LogFile -Encoding UTF8
    throw "Oracle не подтвердил готовность. Проверь: docker logs $Container."
}
function Get-OracleDataMount([string]$Container) {
    # Read Mounts as JSON, then filter in PowerShell. This avoids Docker Go-template
    # parsing problems with a conditional Docker Go-template.
    $raw = & docker inspect --format '{{json .Mounts}}' $Container 2>&1
    $code = $LASTEXITCODE
    $rawText = ($raw | ForEach-Object { [string]$_ }) -join [Environment]::NewLine
    if ($code -ne 0) {
        throw "Не удалось получить docker inspect для контейнера $Container. Ответ: $rawText"
    }
    try {
        $mounts = ConvertFrom-Json -InputObject $rawText -ErrorAction Stop
    }
    catch {
        throw "Docker вернул некорректный JSON списка Mounts для $Container. Ответ: $rawText"
    }
    $found = @($mounts | Where-Object { $_.Destination -eq '/opt/oracle/oradata' })
    if ($found.Count -gt 0) { return $found[0] }
    return $null
}

function SecureStringToPlain([Security.SecureString]$Secure) {
    $ptr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($Secure)
    try { return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr) }
    finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr) }
}
function Copy-And-Stage {
    New-Item -ItemType Directory -Force -Path $StageParent | Out-Null
    $stageDb = Join-Path $StageParent 'HK_DINAMO_Oracle19c'
    $stageApp = Join-Path $StageParent 'HK_DINAMO_Node_App'
    Copy-Item -LiteralPath $DbRoot -Destination $StageParent -Recurse -Force
    New-Item -ItemType Directory -Force -Path $stageApp | Out-Null
    Copy-Item -LiteralPath (Join-Path $AppRoot 'db') -Destination $stageApp -Recurse -Force
    return @{ Db=$stageDb; App=$stageApp }
}
function Write-Utf8NoBom([string]$Path, [string]$Text) {
    [System.IO.File]::WriteAllText($Path, $Text, (New-Object System.Text.UTF8Encoding($false)))
}
function Get-OraclePdbCatalog([string]$Container) {
    # Collect database/CDB context and every PDB, including PDB$SEED, for diagnostics.
    $probeName = "hk_dinamo_pdb_probe_$([guid]::NewGuid().ToString('N'))"
    $localPath = Join-Path $env:TEMP "$probeName.sql"
    $remotePath = "/tmp/$probeName.sql"
    $probeSql = @'
WHENEVER SQLERROR EXIT SQL.SQLCODE
SET HEADING OFF
SET FEEDBACK OFF
SET PAGESIZE 0
SET VERIFY OFF
SET ECHO OFF
SET TERMOUT ON
SET TRIMSPOOL ON
SET TRIMOUT ON
SET TAB OFF
SET LINESIZE 300
SELECT 'DATABASE|' || cdb FROM v$database;
SELECT 'CURRENT|' || SYS_CONTEXT('USERENV','CON_NAME') FROM dual;
SELECT 'PDB|' || con_id || '|' || name || '|' || open_mode
FROM v$pdbs
ORDER BY con_id;
EXIT
'@
    try {
        Write-Utf8NoBom $localPath $probeSql
        & docker cp $localPath "${Container}:$remotePath" 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) {
            throw "Не удалось передать SQL-проверку PDB в контейнер $Container."
        }

        $output = @(& docker exec -u oracle -e "NLS_LANG=$NlsLang" $Container bash -lc "sqlplus -s / as sysdba @$remotePath" 2>&1)
        $exitCode = $LASTEXITCODE
        $outputText = ($output | ForEach-Object { [string]$_ }) -join [Environment]::NewLine
        if ($exitCode -ne 0 -or $outputText -match '(?m)ORA-\d{5}|SP2-\d{4}') {
            throw "Не удалось прочитать сведения о PDB в контейнере $Container. Ответ Oracle: $outputText"
        }

        $cdbMode = 'UNKNOWN'
        $currentContainer = 'UNKNOWN'
        $allPdbs = @()
        foreach ($line in $output) {
            $value = ([string]$line).Trim()
            if ($value -match '^DATABASE\|([A-Z]+)$') {
                $cdbMode = $Matches[1]
            }
            elseif ($value -match '^CURRENT\|(.+)$') {
                $currentContainer = $Matches[1].Trim()
            }
            elseif ($value -match '^PDB\|(\d+)\|([A-Za-z][A-Za-z0-9_$#]*)\|([A-Z ]+)$') {
                $allPdbs += [pscustomobject]@{
                    ConId = [int]$Matches[1]
                    Name = $Matches[2].ToUpperInvariant()
                    OpenMode = $Matches[3].Trim().ToUpperInvariant()
                }
            }
        }
        $userPdbs = @($allPdbs | Where-Object { $_.ConId -gt 2 })
        return [pscustomobject]@{
            Cdb = $cdbMode
            CurrentContainer = $currentContainer
            AllPdbs = @($allPdbs)
            UserPdbs = @($userPdbs)
            RawOutput = $outputText
        }
    }
    finally {
        if (Test-Path -LiteralPath $localPath) {
            Remove-Item -LiteralPath $localPath -Force -ErrorAction SilentlyContinue
        }
        & docker exec -u root $Container bash -lc "rm -f '$remotePath'" *> $null
    }
}
function Prepare-WebSql([string]$StageApp, [string]$WebPassword, [string]$OwnerPassword, [string]$Pdb, [bool]$FullInstall) {
    $webUserFile = Join-Path $StageApp 'db\02_create_web_user.sql'
    $webUserSql = [System.IO.File]::ReadAllText($webUserFile, [System.Text.Encoding]::UTF8)
    $webUserSql = $webUserSql.Replace('ChangeMe_WebApp_19c!', $WebPassword).Replace('SET ECHO ON','SET ECHO OFF')
    Write-Utf8NoBom $webUserFile $webUserSql
$wrapper = @"
WHENEVER SQLERROR EXIT SQL.SQLCODE
SET ECHO OFF
SET DEFINE OFF
SET SERVEROUTPUT ON
CONNECT / AS SYSDBA
ALTER SESSION SET CONTAINER = $Pdb;
DECLARE
  v_charset VARCHAR2(30);
  v_owner   NUMBER;
BEGIN
  SELECT value INTO v_charset FROM nls_database_parameters WHERE parameter='NLS_CHARACTERSET';
  IF v_charset <> 'AL32UTF8' THEN
    RAISE_APPLICATION_ERROR(-20210,'NLS_CHARACTERSET must be AL32UTF8; found '||v_charset);
  END IF;
  SELECT COUNT(*) INTO v_owner FROM dba_users WHERE username='HK_DINAMO';
  IF v_owner = 0 THEN
    RAISE_APPLICATION_ERROR(-20211,'HK_DINAMO schema not found in this PDB.');
  END IF;
END;
/
CONNECT HK_DINAMO/$OwnerPassword@//localhost:1521/$Pdb
@/tmp/HK_DINAMO_Node_App/db/01_web_app_api.sql
@/tmp/HK_DINAMO_Node_App/db/04_repair_demo_data.sql
CONNECT / AS SYSDBA
ALTER SESSION SET CONTAINER = $Pdb;
@/tmp/HK_DINAMO_Node_App/db/02_create_web_user.sql
CONNECT HK_DINAMO/$OwnerPassword@//localhost:1521/$Pdb
@/tmp/HK_DINAMO_Node_App/db/03_verify_web_app.sql
@/tmp/HK_DINAMO_Node_App/db/05_check_seed_counts.sql
EXIT
"@
    Write-Utf8NoBom (Join-Path $StageApp 'run_web_install.sql') $wrapper
}
function Run-WebInstall([string]$Container) {
    Invoke-Docker @('exec','-u','root',$Container,'bash','-lc','mkdir -p /opt/oracle/json /opt/oracle/backup && chown -R oracle:oinstall /opt/oracle/json /opt/oracle/backup') 'Подготавливаю каталоги JSON и резервных копий'
    Invoke-Docker @('cp',(Join-Path $StageParent 'HK_DINAMO_Node_App'),"${Container}:/tmp/") 'Копирую SQL-шлюз Node.js в контейнер'
    Invoke-Docker @('cp',(Join-Path $DbRoot '05_json\players_import.json'),"${Container}:/opt/oracle/json/players_import.json") 'Копирую пример JSON-импорта'
    Invoke-Docker @('exec','-u','oracle','-e',"NLS_LANG=$NlsLang",'-e','LANG=C.UTF-8',$Container,'bash','-lc','sqlplus -s /nolog @/tmp/HK_DINAMO_Node_App/run_web_install.sql') 'Устанавливаю PKG_WEB_API, 10 000 мест и HK_WEB_APP'
}
function Write-AppEnv([string]$AppPassword, [string]$ConnectString, [string]$SetupToken, [string]$SessionSecret) {
    $envText = @"
DB_USER=HK_WEB_APP
DB_PASSWORD=$AppPassword
DB_CONNECT_STRING=$ConnectString
DB_POOL_MIN=1
DB_POOL_MAX=6
SETUP_TOKEN=$SetupToken
SESSION_SECRET=$SessionSecret
PORT=3000
NODE_ENV=development
APP_BASE_URL=http://localhost:3000
"@
    Write-Utf8NoBom (Join-Path $AppRoot '.env') $envText
}

try {
    Write-Host '============================================================' -ForegroundColor Cyan
    Write-Host '  HK DINAMO - единая установка Oracle 19c + Node.js сайта' -ForegroundColor Cyan
    Write-Host '============================================================' -ForegroundColor Cyan
    if (-not (Test-Path (Join-Path $DbRoot '04_data\install_all.sql'))) { throw 'Не найдена папка HK_DINAMO_Oracle19c рядом с установщиком.' }
    if (-not (Test-Path (Join-Path $AppRoot 'db\01_web_app_api.sql'))) { throw 'Не найдена папка HK_DINAMO_Node_App рядом с установщиком.' }

    $docker = & docker version --format '{{.Server.Version}}' 2>&1
    if ($LASTEXITCODE -ne 0) { throw 'Docker Engine недоступен. Запусти Docker Desktop и дождись Engine running.' }
    Write-Log "Docker Engine: $docker"
    Write-Host "`nРежим установки:"
    Write-Host '  [1] Новый контейнер Oracle 19c + полная БД + сайт (чистая установка)'
    Write-Host '  [2] Существующий контейнер + полная БД в пустой PDB + сайт'
    Write-Host '  [3] Уже установленная схема HK_DINAMO: добавить сайт, сохранить данные'
    Write-Host '  [4] Восстановить незавершённую установку: существующая PDB и пользователь HK_DINAMO, таблицы ещё не созданы'
    $mode = Read-Host 'Выбери режим 1, 2, 3 или 4 (по умолчанию 3)'
    if ([string]::IsNullOrWhiteSpace($mode)) { $mode='3' }
    if ($mode -notin @('1','2','3','4')) { throw 'Нужно выбрать 1, 2, 3 или 4.' }

    $container = 'oracle19c-dinamo'
    $pdb = 'ORCLPDB1'
    $port = 1521
    $ownerPassword = $null
    $sysPassword = $null
    $fullInstall = $mode -in @('1','2')
    $schemaInstall = $mode -in @('1','2','4')

    if ($mode -eq '1') {
        $container = Read-Host 'Имя нового контейнера (Enter = oracle19c-dinamo)'
        if ([string]::IsNullOrWhiteSpace($container)) { $container='oracle19c-dinamo' }
        if ($container -notmatch '^[A-Za-z0-9][A-Za-z0-9_.-]{0,62}$') { throw 'Недопустимое имя контейнера.' }
        $pdb = Read-Host 'Имя PDB (Enter = ORCLPDB1)'
        if ([string]::IsNullOrWhiteSpace($pdb)) { $pdb='ORCLPDB1' }
        $pdb = $pdb.ToUpperInvariant()
        if ($pdb -notmatch '^[A-Z][A-Z0-9_$#]{0,29}$') { throw 'Недопустимое имя PDB.' }
        $portText = Read-Host 'Порт на компьютере (Enter = 1521)'
        if ($portText) { $port=[int]$portText }
        if ($port -lt 1024 -or $port -gt 65535) { throw 'Укажи порт 1024-65535.' }
        $existing = & docker ps -a --filter "name=^/$container$" --format '{{.Names}}'
        if ($existing -contains $container) { throw "Контейнер $container уже существует. Не удаляю его; выбери другое имя или режим 3." }
        $defaultDataPath = 'D:\HK_DINAMO\Oracle\data'
        if (-not (Test-Path -LiteralPath 'D:\')) {
            throw 'Диск D: не найден. Подключи диск D: и повтори установку.'
        }
        $dataPath = Read-Host "Путь для файлов БД (Enter = $defaultDataPath)"
        if ([string]::IsNullOrWhiteSpace($dataPath)) { $dataPath = $defaultDataPath }
        if (-not [System.IO.Path]::IsPathRooted($dataPath) -or $dataPath -notmatch '^[A-Za-z]:\\') {
            throw 'Укажи абсолютный путь на локальном диске, например D:\HK_DINAMO\Oracle\data.'
        }
        if (Test-Path -LiteralPath $dataPath) {
            $items = @(Get-ChildItem -LiteralPath $dataPath -Force -ErrorAction SilentlyContinue)
            if ($items.Count -gt 0) { throw "Каталог $dataPath не пуст. Я не буду использовать или перезаписывать существующие файлы Oracle." }
        }
        New-Item -ItemType Directory -Force -Path $dataPath | Out-Null
        $sysPassword = New-RandomSafe 24
        Write-Host "`nЕсли docker pull вернёт 401, выполни docker login container-registry.oracle.com и прими условия в Oracle Container Registry." -ForegroundColor Yellow
        Invoke-Docker @('pull',$Image) 'Скачиваю официальный Oracle Database 19c image'
        Invoke-Docker @('run','-d','--name',$container,'--hostname',$container,'--restart','unless-stopped',
            '--publish',"${port}:1521",'--publish','5500:5500',
            '--env','ORACLE_SID=ORCLCDB',"--env","ORACLE_PDB=$pdb","--env","ORACLE_PWD=$sysPassword",
            '--mount',"type=bind,source=$dataPath,target=/opt/oracle/oradata",'--shm-size=2g',$Image) 'Создаю контейнер Oracle 19c'
        $mountInfo = Get-OracleDataMount $container
        if (-not $mountInfo -or $mountInfo.Type -ne 'bind' -or $mountInfo.Destination -ne '/opt/oracle/oradata') {
            throw "Не удалось подтвердить bind mount Oracle data directory. Контейнер оставлен для диагностики; выполни docker inspect $container."
        }
        $mountText = "$($mountInfo.Type)|$($mountInfo.Source)|$($mountInfo.Destination)"
        Write-Log "Проверено подключение каталога Oracle: $mountText"
        Wait-Oracle $container $true
    }
    elseif ($mode -in @('2','3','4')) {
        $prompt = Read-Host 'Имя запущенного Oracle-контейнера (Enter = oracle19c-dinamo)'
        if ($prompt) { $container=$prompt }
        $state = & docker inspect --format '{{.State.Running}}' $container 2>$null
        if ($LASTEXITCODE -ne 0 -or $state -ne 'true') { throw "Контейнер $container не найден или не запущен. Запусти его в Docker Desktop." }

        # Existing-container modes do not relocate Oracle data. Report the actual mount.
        $existingMount = Get-OracleDataMount $container
        if ($existingMount) {
            $existingMountText = "$($existingMount.Type)|$($existingMount.Source)|$($existingMount.Destination)"
            Write-Host "Текущее хранилище Oracle: $existingMountText" -ForegroundColor Cyan
            Write-Log "Existing Oracle data mount: $existingMountText"
            if ($existingMount.Type -ne 'bind' -or $existingMount.Source -notmatch '(?i)(D:[\\/]|/host/d/)') {
                Write-Host 'ВНИМАНИЕ: текущий контейнер не показывает bind mount на диске D:. Режимы 2/3 не переносят существующие файлы БД.' -ForegroundColor Yellow
            }
        }
        else {
            Write-Host 'ВНИМАНИЕ: у контейнера не найден отдельный bind mount для /opt/oracle/oradata. Данные могут находиться во внутреннем хранилище Docker.' -ForegroundColor Yellow
        }

        $pdbIn = Read-Host 'Имя PDB (Enter = ORCLPDB1; при одной PDB установщик выберет её автоматически)'
        if ($pdbIn) { $pdb=$pdbIn.ToUpperInvariant() }
        if ($pdb -notmatch '^[A-Z][A-Z0-9_$#]{0,29}$') { throw 'Недопустимое имя PDB.' }
        $portIn = Read-Host 'Опубликованный порт listener (Enter = 1521)'
        if ($portIn) { $port=[int]$portIn }
        if ($port -lt 1 -or $port -gt 65535) { throw 'Недопустимый порт.' }
        $sqlplus = & docker exec -u oracle $container bash -lc 'command -v sqlplus' 2>&1
        if ($LASTEXITCODE -ne 0 -or -not $sqlplus) { throw 'В контейнере не найден SQL*Plus.' }
        Wait-Oracle $container $false

        # Validate the requested PDB name against the actual PDB list.
        # If there is exactly one user PDB, select it automatically.
        $pdbInfo = Get-OraclePdbCatalog $container
        $pdbCatalog = @($pdbInfo.UserPdbs)
        if ($pdbCatalog.Count -eq 0) {
            $allPdbText = if (@($pdbInfo.AllPdbs).Count -gt 0) {
                (@($pdbInfo.AllPdbs | ForEach-Object { "con_id=$($_.ConId): $($_.Name) [$($_.OpenMode)]" })) -join '; '
            } else { '(Oracle не вернул ни одной строки из v$pdbs)' }
            $diagnostic = "CDB=$($pdbInfo.Cdb); текущий контейнер=$($pdbInfo.CurrentContainer); PDB=$allPdbText; raw=$($pdbInfo.RawOutput)"
            throw "В контейнере $container нет пользовательской PDB (con_id > 2). Диагностика: $diagnostic. Режим 2 требует существующую PDB. Для чистой установки с созданием PDB выбери режим 1; он создаст новый контейнер и подключит D:\HK_DINAMO\Oracle\data."
        }
        $pdbMatch = @($pdbCatalog | Where-Object { $_.Name -ieq $pdb })
        if ($pdbMatch.Count -gt 0) {
            $pdb = $pdbMatch[0].Name
        }
        elseif ($pdbCatalog.Count -eq 1) {
            $oldPdb = $pdb
            $pdb = $pdbCatalog[0].Name
            Write-Host "PDB '$oldPdb' не найдена. В контейнере есть только '$pdb' — использую её." -ForegroundColor Yellow
            Write-Log "PDB auto-selected: $pdb (requested: $oldPdb)"
        }
        else {
            $availablePdbs = ($pdbCatalog | ForEach-Object { "$($_.Name) [$($_.OpenMode)]" }) -join ', '
            throw "PDB '$pdb' не найдена. Доступные PDB: $availablePdbs. Запусти установщик повторно и введи одно из этих имён."
        }
        Write-Log "Целевая PDB: $pdb"

        if ($mode -eq '3') {
            $secure = Read-Host 'Пароль владельца схемы HK_DINAMO (ввод скрыт)' -AsSecureString
            $ownerPassword = SecureStringToPlain $secure
            if ([string]::IsNullOrWhiteSpace($ownerPassword)) { throw 'Пароль HK_DINAMO не может быть пустым.' }
        }
        elseif ($mode -eq '4') {
            Write-Host 'Режим восстановления: пароль HK_DINAMO будет сброшен через SYSDBA. Пользователи и роли повторно создаваться не будут.' -ForegroundColor Yellow
            $ownerPassword = New-RandomSafe 24
        }
    }

    $ownerPasswordForConnect = $ownerPassword
    $mainPassword = $null; $adminPassword = $null; $userPassword = $null
    if ($fullInstall) {
        $ownerPasswordForConnect = New-RandomSafe 20
        $mainPassword = New-RandomSafe 20
        $adminPassword = New-RandomSafe 20
        $userPassword = New-RandomSafe 20
    }
    elseif ($mode -eq '4') {
        $ownerPasswordForConnect = $ownerPassword
    }
    # Keep a previously configured web password to make reruns reproducible; otherwise generate a fresh one.
    $existingEnv = Join-Path $AppRoot '.env'
    $webPassword = $null; $setupToken=$null; $sessionSecret=$null
    if (Test-Path $existingEnv) {
        $oldEnv = Get-Content -LiteralPath $existingEnv -Raw -Encoding UTF8
        if ($oldEnv -match '(?m)^DB_PASSWORD=(.+)$') { $webPassword=$Matches[1].Trim() }
        if ($oldEnv -match '(?m)^SETUP_TOKEN=(.+)$') { $setupToken=$Matches[1].Trim() }
        if ($oldEnv -match '(?m)^SESSION_SECRET=(.+)$') { $sessionSecret=$Matches[1].Trim() }
    }
    if ([string]::IsNullOrWhiteSpace($webPassword)) { $webPassword=New-RandomSafe 24 }
    if ([string]::IsNullOrWhiteSpace($setupToken)) { $setupToken=New-Secret 32 }
    if ([string]::IsNullOrWhiteSpace($sessionSecret)) { $sessionSecret=New-Secret 32 }

    # Prepare a temporary UTF-8 stage, without a BOM in SQL*Plus scripts.
    $stage = Copy-And-Stage
    if ($fullInstall) {
        $userSqlPath = Join-Path $stage.Db '00_sys\\00_create_users_roles.sql'
        $userSql = [System.IO.File]::ReadAllText($userSqlPath,[System.Text.Encoding]::UTF8)
        $userSql = $userSql.Replace('ChangeMe_Dinamo_19c!',$ownerPasswordForConnect).Replace('ChangeMe_MainAdmin_19c!',$mainPassword).Replace('ChangeMe_Admin_19c!',$adminPassword).Replace('ChangeMe_User_19c!',$userPassword).Replace('SET ECHO ON','SET ECHO OFF')
        Write-Utf8NoBom $userSqlPath $userSql
$sysWrapper = @"
WHENEVER SQLERROR EXIT SQL.SQLCODE
SET ECHO OFF
SET DEFINE OFF
SET SERVEROUTPUT ON
DECLARE
  v_version VARCHAR2(50);
BEGIN
  SELECT version INTO v_version FROM v`$instance;
  IF SUBSTR(v_version,1,2) <> '19' THEN
    RAISE_APPLICATION_ERROR(-20001,'This installer requires Oracle Database 19c.');
  END IF;
END;
/
DECLARE
  v_mode  VARCHAR2(20);
  v_count NUMBER;
  v_names VARCHAR2(4000);
BEGIN
  SELECT COUNT(*) INTO v_count
    FROM v`$pdbs
   WHERE name='$pdb'
     AND con_id > 2;
  IF v_count = 0 THEN
    SELECT NVL(LISTAGG(name, ', ') WITHIN GROUP (ORDER BY name), '(none)')
      INTO v_names
      FROM v`$pdbs
     WHERE con_id > 2;
    RAISE_APPLICATION_ERROR(-20004,'PDB $pdb not found. Available user PDBs: ' || v_names);
  END IF;
  SELECT open_mode INTO v_mode FROM v`$pdbs WHERE name='$pdb' AND con_id > 2;
  IF v_mode='MOUNTED' THEN
    EXECUTE IMMEDIATE 'ALTER PLUGGABLE DATABASE $pdb OPEN';
  ELSIF v_mode='READ ONLY' THEN
    EXECUTE IMMEDIATE 'ALTER PLUGGABLE DATABASE $pdb CLOSE IMMEDIATE';
    EXECUTE IMMEDIATE 'ALTER PLUGGABLE DATABASE $pdb OPEN READ WRITE';
  END IF;
END;
/
ALTER SESSION SET CONTAINER = $pdb;
DECLARE
  v_charset VARCHAR2(30);
  v_count NUMBER;
BEGIN
  SELECT value INTO v_charset FROM nls_database_parameters WHERE parameter='NLS_CHARACTERSET';
  IF v_charset <> 'AL32UTF8' THEN
    RAISE_APPLICATION_ERROR(-20002,'Database charset must be AL32UTF8. Found: '||v_charset);
  END IF;
  SELECT COUNT(*) INTO v_count FROM all_users WHERE username='HK_DINAMO';
  IF v_count > 0 THEN
    RAISE_APPLICATION_ERROR(-20003,'HK_DINAMO already exists. Use recovery mode 4 or mode 3.');
  END IF;
END;
/
@/tmp/HK_DINAMO_Oracle19c/00_sys/00_create_users_roles.sql
EXIT
"@
        Write-Utf8NoBom (Join-Path $stage.Db 'run_sys_install.sql') $sysWrapper
    }

    if ($schemaInstall) {
        $schemaWrapper = @"
WHENEVER SQLERROR EXIT SQL.SQLCODE
SET ECHO OFF
SET DEFINE OFF
SET SERVEROUTPUT ON
CONNECT HK_DINAMO/$ownerPasswordForConnect@//localhost:1521/$pdb
@/tmp/HK_DINAMO_Oracle19c/01_schema/01_tables.sql
@/tmp/HK_DINAMO_Oracle19c/02_logic/02_triggers.sql
@/tmp/HK_DINAMO_Oracle19c/02_logic/03_functions.sql
@/tmp/HK_DINAMO_Oracle19c/02_logic/04_views.sql
@/tmp/HK_DINAMO_Oracle19c/02_logic/05_packages.sql
@/tmp/HK_DINAMO_Oracle19c/04_data/06_seed_demo_data.sql
@/tmp/HK_DINAMO_Oracle19c/03_security/07_grants.sql
@/tmp/HK_DINAMO_Oracle19c/06_performance/07_load_100k_tickets.sql
@/tmp/HK_DINAMO_Oracle19c/verify_install.sql
EXIT
"@
Write-Utf8NoBom (Join-Path $stage.Db 'verify_install.sql') @'
WHENEVER SQLERROR EXIT SQL.SQLCODE
SET SERVEROUTPUT ON
DECLARE
  v_invalid NUMBER;
  v_errors  NUMBER;
BEGIN
  SELECT COUNT(*) INTO v_invalid FROM user_objects WHERE status <> 'VALID';
  SELECT COUNT(*) INTO v_errors  FROM user_errors;
  DBMS_OUTPUT.PUT_LINE('INVALID_OBJECTS='||v_invalid);
  DBMS_OUTPUT.PUT_LINE('COMPILE_ERRORS='||v_errors);
  IF v_invalid > 0 OR v_errors > 0 THEN
    RAISE_APPLICATION_ERROR(-20010,'Invalid objects or compilation errors found.');
  END IF;
END;
/
SELECT table_name FROM user_tables ORDER BY table_name;
'@
        Write-Utf8NoBom (Join-Path $stage.Db 'run_schema_install.sql') $schemaWrapper
        if ($mode -eq '4') {
            $resetOwnerSql = @"
WHENEVER SQLERROR EXIT SQL.SQLCODE
SET ECHO OFF
SET DEFINE OFF
ALTER SESSION SET CONTAINER = $pdb;
DECLARE
  v_count NUMBER;
BEGIN
  SELECT COUNT(*) INTO v_count FROM dba_users WHERE username='HK_DINAMO';
  IF v_count = 0 THEN
    RAISE_APPLICATION_ERROR(-20020,'HK_DINAMO user does not exist in PDB $pdb.');
  END IF;
  SELECT COUNT(*) INTO v_count FROM dba_tables WHERE owner='HK_DINAMO';
  IF v_count > 0 THEN
    RAISE_APPLICATION_ERROR(-20021,'HK_DINAMO already contains tables. Recovery mode 4 is only for an empty schema; use mode 3 to preserve existing data.');
  END IF;
END;
/
ALTER USER HK_DINAMO IDENTIFIED BY "$ownerPasswordForConnect";
EXIT
"@
            Write-Utf8NoBom (Join-Path $stage.Db 'run_reset_owner.sql') $resetOwnerSql
        }
    }

    # Prepare app SQL wrapper; it also creates/refreshes HK_WEB_APP with a generated strong password.
    $webStage = $stage.App
    Prepare-WebSql $webStage $webPassword $ownerPasswordForConnect $pdb $fullInstall

    # Copy to container and prepare JSON/backup directories.
    Invoke-Docker @('exec','-u','root',$container,'bash','-lc','mkdir -p /opt/oracle/json /opt/oracle/backup && chown -R oracle:oinstall /opt/oracle/json /opt/oracle/backup') 'Подготавливаю каталоги JSON/backup'
    if ($schemaInstall) {
        Invoke-Docker @('cp',$stage.Db,"${container}:/tmp/") 'Копирую исходные SQL проекта базы'
    }
    Invoke-Docker @('cp',$stage.App,"${container}:/tmp/") 'Копирую SQL шлюза Node.js'
    Invoke-Docker @('cp',(Join-Path $DbRoot '05_json\players_import.json'),"${container}:/opt/oracle/json/players_import.json") 'Копирую пример JSON-файла'

    if ($fullInstall) {
        Invoke-Docker @('exec','-u','oracle','-e',"NLS_LANG=$NlsLang",'-e','LANG=C.UTF-8',$container,'bash','-lc','sqlplus -s / as sysdba @/tmp/HK_DINAMO_Oracle19c/run_sys_install.sql') 'Создаю схему, роли и Oracle-учётные записи'
    }
    elseif ($mode -eq '4') {
        Invoke-Docker @('exec','-u','oracle','-e',"NLS_LANG=$NlsLang",'-e','LANG=C.UTF-8',$container,'bash','-lc','sqlplus -s / as sysdba @/tmp/HK_DINAMO_Oracle19c/run_reset_owner.sql') 'Восстанавливаю пароль существующего HK_DINAMO'
    }
    if ($schemaInstall) {
        Invoke-Docker @('exec','-u','oracle','-e',"NLS_LANG=$NlsLang",'-e','LANG=C.UTF-8',$container,'bash','-lc','sqlplus -s /nolog @/tmp/HK_DINAMO_Oracle19c/run_schema_install.sql') 'Создаю таблицы, PL/SQL, демо-данные и 100 000 тестовых билетов'
    }
    Invoke-Docker @('exec','-u','oracle','-e',"NLS_LANG=$NlsLang",'-e','LANG=C.UTF-8',$container,'bash','-lc','sqlplus -s /nolog @/tmp/HK_DINAMO_Node_App/run_web_install.sql') 'Устанавливаю PKG_WEB_API, демонстрационные места и HK_WEB_APP'
    Invoke-Docker @('exec','-u','root',$container,'bash','-lc','rm -rf /tmp/HK_DINAMO_Node_App /tmp/HK_DINAMO_Oracle19c') 'Удаляю временные SQL-файлы установки с данными подключения'

    # Generate Node.js .env only after Oracle SQL installation succeeded.
    $connectString = "127.0.0.1:${port}/${pdb}"
    Write-AppEnv $webPassword $connectString $setupToken $sessionSecret
    $creds = @(
      'HK DINAMO - application connection details',
      "Created: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')",
      "Container: $container",
      "PDB service: $pdb",
      "Connection: $connectString",
      'DB_USER=HK_WEB_APP',
      "DB_PASSWORD=$webPassword",
      "SETUP_TOKEN=$setupToken",
      "SESSION_SECRET=$sessionSecret"
    )
    if ($schemaInstall) {
      $creds += "HK_DINAMO=$ownerPasswordForConnect"
      if ($fullInstall) {
        $creds += "HK_MAIN_ADMIN=$mainPassword"
        $creds += "HK_ADMIN=$adminPassword"
        $creds += "HK_USER=$userPassword"
        if ($sysPassword) { $creds += "SYS=$sysPassword" }
      }
    }
    $creds += @(
      '',
      'Keep this file private. Never share it or the .env file.'
    )
    [System.IO.File]::WriteAllLines($CredFile,$creds,([System.Text.UTF8Encoding]::new($true)))

    Write-Host "`nSQL installation is complete. Credentials saved: $CredFile" -ForegroundColor Green
    Write-Host "App configuration written to: $(Join-Path $AppRoot '.env')" -ForegroundColor Green
    Write-Host "Oracle connection: $connectString" -ForegroundColor Green

    # Install Node dependencies automatically only if Node 22+ is already installed.
    $node = Get-Command node.exe -ErrorAction SilentlyContinue
    $npm = Get-Command npm.cmd -ErrorAction SilentlyContinue
    if ($node -and $npm) {
        $ver = (& node.exe --version 2>&1 | Out-String).Trim()
        if ($ver -match '^v(\d+)\.' -and [int]$Matches[1] -ge 22) {
            Push-Location $AppRoot
            try {
                Write-Host "`nNode.js найден: $ver. Устанавливаю npm-зависимости..." -ForegroundColor Cyan
                & npm.cmd install
                if ($LASTEXITCODE -ne 0) { Write-Host 'npm install failed; database is installed. Run npm install inside HK_DINAMO_Node_App.' -ForegroundColor Yellow }
                else {
                    & npm.cmd run check
                    if ($LASTEXITCODE -eq 0) { Write-Host 'JavaScript syntax check passed.' -ForegroundColor Green }
                    else { Write-Host 'JavaScript check failed; see npm output.' -ForegroundColor Yellow }
                }
            } finally { Pop-Location }
        } else { Write-Host 'Node.js 22+ is required. Install it, then run 02_START_WEB_APP.bat.' -ForegroundColor Yellow }
    } else { Write-Host 'Node.js is not installed. Install Node.js 22+, then run 02_START_WEB_APP.bat.' -ForegroundColor Yellow }

    Write-Host "`n============================================================" -ForegroundColor Green
    Write-Host 'УСТАНОВКА БД И SQL-ШЛЮЗА ПРИЛОЖЕНИЯ ЗАВЕРШЕНА' -ForegroundColor Green
    Write-Host 'Следующий шаг: запусти 02_START_WEB_APP.bat или HK_DINAMO_Node_App\start.bat.' -ForegroundColor Green
    Write-Host 'Затем открой http://localhost:3000/setup для создания MAIN_ADMIN.' -ForegroundColor Green
    Write-Host "Журнал: $LogFile" -ForegroundColor Gray
    Write-Host "Доступы: $CredFile" -ForegroundColor Gray
}
catch {
    $msg = $_.Exception.Message
    Write-Host "`nОШИБКА: $msg" -ForegroundColor Red
    Write-Host "Журнал: $LogFile" -ForegroundColor Yellow
    exit 1
}
finally {
    if (Test-Path $StageParent) { Remove-Item -LiteralPath $StageParent -Recurse -Force -ErrorAction SilentlyContinue }
    Write-Host ''
    Write-Host 'Окно установщика останется открытым. Скопируй текст ошибки или результата.' -ForegroundColor Yellow
    try { [void](Read-Host 'Нажми Enter, когда закончишь просмотр, чтобы закрыть окно') } catch { }
}
