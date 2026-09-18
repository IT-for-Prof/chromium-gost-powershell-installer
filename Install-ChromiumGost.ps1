[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter()]
    [ValidatePattern('^v?\d+\.\d+\.\d+\.\d+$')]
    [string]$Version,

    [Parameter()]
    [ValidatePattern('^[0-9a-fA-F]{64}$')]
    [string]$Sha256,

    [Parameter()]
    [switch]$Force,

    [Parameter()]
    [string]$LogPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:TaskName = 'Chromium-GOST daily update'
$script:TaskScriptPath = $null
$script:TaskLogPath = $null

$script:ApiBase = 'https://api.github.com/repos/deemru/Chromium-Gost/releases'
$script:UserAgent = 'chromium-gost-powershell-installer'
$script:TempDirectory = $null

function Write-Log {
    param(
        [Parameter(Mandatory)] [string]$Message,
        [ValidateSet('INFO', 'WARN', 'ERROR')] [string]$Level = 'INFO'
    )

    $line = '{0:u} [{1}] {2}' -f (Get-Date), $Level, $Message
    Write-Host $line
    if ($LogPath) {
        Add-Content -LiteralPath $LogPath -Value $line -Encoding UTF8
    }
}

function Get-VersionText {
    param([AllowNull()] [object]$Value)

    if ($null -eq $Value) { return $null }
    $match = [regex]::Match([string]$Value, '\d+(?:\.\d+){1,3}')
    if ($match.Success) { return $match.Value }
    return $null
}

function Get-InstalledChromiumGostVersion {
    $versions = [System.Collections.Generic.List[version]]::new()
    $registryPaths = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )

    foreach ($path in $registryPaths) {
        foreach ($entry in @(Get-ItemProperty -Path $path -ErrorAction SilentlyContinue)) {
            $displayName = if ($entry.PSObject.Properties['DisplayName']) { [string]$entry.DisplayName } else { '' }
            if ($displayName -match '(?i)chromium.*gost|gost.*chromium') {
                $displayVersion = if ($entry.PSObject.Properties['DisplayVersion']) { $entry.DisplayVersion } else { $null }
                $version = Get-VersionText $displayVersion
                if ($version) { $versions.Add([version]$version) }
            }
        }
    }

    $candidatePaths = @(
        "$env:ProgramFiles\Chromium\Application\chrome.exe",
        "${env:ProgramFiles(x86)}\Chromium\Application\chrome.exe",
        "$env:ProgramFiles\Chromium-Gost\Application\chrome.exe",
        "${env:ProgramFiles(x86)}\Chromium-Gost\Application\chrome.exe"
    )

    foreach ($path in $candidatePaths) {
        $file = Get-Item -LiteralPath $path -ErrorAction SilentlyContinue
        if (-not $file) { continue }
        $version = Get-VersionText $file.VersionInfo.ProductVersion
        if ($version) { $versions.Add([version]$version) }
    }

    if ($versions.Count -gt 0) { return ($versions | Sort-Object -Descending | Select-Object -First 1).ToString() }
    return $null
}

function Get-Release {
    param([AllowNull()] [string]$RequestedVersion)

    $uri = if ($RequestedVersion) {
        "$script:ApiBase/tags/$RequestedVersion"
    } else {
        "$script:ApiBase/latest"
    }

    Write-Log "Получение релиза: $uri"
    Invoke-RestMethod -Uri $uri -Headers @{
        Accept = 'application/vnd.github+json'
        'User-Agent' = $script:UserAgent
    } -TimeoutSec 60
}

function Get-InstallerAsset {
    param([Parameter(Mandatory)] [object]$Release)

    $assets = @($Release.assets | Where-Object {
        $_.name -match '^chromium-gost-.+-windows-amd64-installer\.exe$'
    })
    if ($assets.Count -ne 1) {
        throw "Ожидался ровно один Windows x64 installer, найдено: $($assets.Count)."
    }
    return $assets[0]
}

function Stop-ChromiumProcesses {
    $processes = @(Get-Process -Name chrome, chromium, chromium-gost -ErrorAction SilentlyContinue)
    foreach ($process in $processes) {
        Write-Log "Завершение процесса $($process.ProcessName) (PID $($process.Id))"
        Stop-Process -Id $process.Id -Force
    }
}

function Wait-InstalledVersion {
    param(
        [Parameter(Mandatory)] [string]$ExpectedVersion,
        [int]$TimeoutSeconds = 180
    )

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    do {
        $version = Get-InstalledChromiumGostVersion
        if ($version -eq $ExpectedVersion) { return $version }
        if ((Get-Date) -ge $deadline) { break }
        Start-Sleep -Seconds 5
    } while ($true)

    return $version
}

function Ensure-UpdateTask {
    $sourcePath = [IO.Path]::GetFullPath($PSCommandPath)
    $targetDirectory = Split-Path -Parent $script:TaskScriptPath
    New-Item -ItemType Directory -Path $targetDirectory -Force | Out-Null
    if ($sourcePath -ne [IO.Path]::GetFullPath($script:TaskScriptPath)) {
        Copy-Item -LiteralPath $sourcePath -Destination $script:TaskScriptPath -Force
    }
    $action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument (
        '-NoProfile -ExecutionPolicy Bypass -File "{0}" -LogPath "{1}"' -f $script:TaskScriptPath, $script:TaskLogPath
    )
    $trigger = New-ScheduledTaskTrigger -Daily -At '03:00' -RandomDelay (New-TimeSpan -Minutes 30)
    $settings = New-ScheduledTaskSettingsSet -MultipleInstances IgnoreNew -StartWhenAvailable
    Register-ScheduledTask -TaskName $script:TaskName -Action $action -Trigger $trigger -Settings $settings -User 'SYSTEM' -RunLevel Highest -Force | Out-Null
    Write-Log "Задача обновления зарегистрирована: ежедневно около 03:00, случайная задержка до 30 минут."
}

try {
    if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) {
        throw 'Поддерживается только Windows.'
    }
    if ([Runtime.InteropServices.RuntimeInformation]::OSArchitecture -ne [Runtime.InteropServices.Architecture]::X64) {
        throw 'Поддерживается только Windows x64 (ARM64 не поддерживается).'
    }

    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw 'Скрипт необходимо запускать от имени администратора.'
    }

    if ($LogPath) {
        $logParent = Split-Path -Parent $LogPath
        if ($logParent) {
            New-Item -ItemType Directory -Path $logParent -Force | Out-Null
        }
    }

    $script:TaskScriptPath = Join-Path $env:ProgramData 'Chromium-Gost\Install-ChromiumGost.ps1'
    $script:TaskLogPath = Join-Path $env:ProgramData 'Chromium-Gost\update.log'

    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $requestedVersion = if ($Version) { $Version.TrimStart('v') } else { $null }
    if ($Version -and $Sha256 -eq '') {
        throw 'При указании -Version необходимо указать -Sha256.'
    }
    if (-not $WhatIfPreference) { Ensure-UpdateTask }

    $release = Get-Release $requestedVersion
    $releaseVersion = Get-VersionText $release.tag_name
    if (-not $releaseVersion) { throw 'GitHub API не вернул корректную версию релиза.' }
    if ($requestedVersion -and $releaseVersion -ne $requestedVersion) {
        throw "GitHub вернул версию $releaseVersion вместо $requestedVersion."
    }

    $asset = Get-InstallerAsset $release
    if ([IO.Path]::GetFileName($asset.name) -ne $asset.name) {
        throw "Некорректное имя asset: $($asset.name)"
    }
    $assetDigest = if ($asset.PSObject.Properties['digest']) { [string]$asset.digest } else { '' }
    $expectedHash = if ($Sha256) { $Sha256.ToLowerInvariant() } else { $assetDigest -replace '^sha256:', '' }
    if ($expectedHash -notmatch '^[0-9a-fA-F]{64}$') {
        throw 'Для выбранного asset отсутствует SHA-256. Укажите -Sha256 вручную.'
    }

    $installedVersion = Get-InstalledChromiumGostVersion
    Write-Log "Релиз: $releaseVersion; asset: $($asset.name); SHA-256: $expectedHash"
    if ($installedVersion) { Write-Log "Установленная версия: $installedVersion" }
    if (-not $Force -and $installedVersion -and $installedVersion -eq $releaseVersion) {
        Write-Log 'Нужная версия уже установлена; установка не требуется.'
        exit 0
    }

    if ($WhatIfPreference) {
        Write-Log 'WhatIf: скачивание и установка пропущены.'
        exit 0
    }

    $script:TempDirectory = Join-Path ([IO.Path]::GetTempPath()) "chromium-gost-$([guid]::NewGuid().ToString('N'))"
    New-Item -ItemType Directory -Path $script:TempDirectory -Force | Out-Null
    $installerPath = Join-Path $script:TempDirectory $asset.name

    Write-Log "Скачивание: $($asset.browser_download_url)"
    Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $installerPath -UseBasicParsing -TimeoutSec 600 -Headers @{
        'User-Agent' = $script:UserAgent
    }

    $actualHash = (Get-FileHash -LiteralPath $installerPath -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actualHash -ne $expectedHash.ToLowerInvariant()) {
        throw "SHA-256 не совпадает: ожидался $expectedHash, получен $actualHash."
    }
    Write-Log "SHA-256 проверен: $actualHash"

    $arguments = @('--system-level', '--install', '--do-not-launch-chrome')
    if (-not $PSCmdlet.ShouldProcess($installerPath, 'Установить Chromium-GOST')) {
        exit 0
    }
    Stop-ChromiumProcesses
    Write-Log "Запуск installer с параметрами: $($arguments -join ' ')"
    $process = Start-Process -FilePath $installerPath -ArgumentList $arguments -Wait -PassThru
    Write-Log "Код возврата installer: $($process.ExitCode)"
    if ($process.ExitCode -ne 0) {
        throw "Installer завершился с кодом $($process.ExitCode)."
    }

    $installedVersion = Wait-InstalledVersion -ExpectedVersion $releaseVersion
    if (-not $installedVersion) {
        throw 'После установки не удалось определить установленную версию Chromium-GOST.'
    }
    if ($installedVersion -ne $releaseVersion) {
        throw "После установки обнаружена версия $installedVersion, ожидалась $releaseVersion."
    }
    Write-Log "Установка подтверждена: $installedVersion"
    exit 0
}
catch {
    try { Write-Log $_.Exception.Message 'ERROR' } catch { Write-Error $_.Exception.Message }
    exit 1
}
finally {
    if ($script:TempDirectory) {
        try {
            $tempDirectory = Get-Item -LiteralPath $script:TempDirectory -ErrorAction SilentlyContinue
            if ($tempDirectory) {
                Remove-Item -LiteralPath $script:TempDirectory -Recurse -Force -ErrorAction Stop
            }
        }
        catch {
            Write-Error "Не удалось удалить временный каталог: $script:TempDirectory. $($_.Exception.Message)"
            exit 1
        }
    }
}
