[CmdletBinding()]
param(
    [switch]$RestartIfRequired
)

$driversPath = Join-Path -Path $PSScriptRoot -ChildPath 'Temp\Drivers'
$logPath = Join-Path -Path $driversPath -ChildPath 'DeploymentLogs'
$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$wrapperLogPath = Join-Path -Path $logPath -ChildPath "Drivers-$timestamp.log"
$sdiConfigPath = $null
$sdiConfigBackupPath = $null

$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator
)

if (-not $isAdmin) {
    Write-Host 'Requesting Administrator privileges...' -ForegroundColor Yellow
    $arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
    if ($RestartIfRequired) {
        $arguments += ' -RestartIfRequired'
    }

    Start-Process -FilePath 'powershell.exe' -Verb RunAs -ArgumentList $arguments
    exit 0
}

if (-not (Test-Path -LiteralPath $driversPath -PathType Container)) {
    throw "SDI directory not found: $driversPath"
}

New-Item -ItemType Directory -Path $logPath -Force -ErrorAction Stop | Out-Null

$transcriptStarted = $false
try {
    Start-Transcript -Path $wrapperLogPath -Force -ErrorAction Stop | Out-Null
    $transcriptStarted = $true

    $is64Bit = [Environment]::Is64BitOperatingSystem
    if ($is64Bit) {
        $sdiCandidates = @(Get-ChildItem -LiteralPath $driversPath -Filter 'SDI_x64_R*.exe' -File -Recurse -ErrorAction SilentlyContinue)
    }
    else {
        $sdiCandidates = @(Get-ChildItem -LiteralPath $driversPath -Filter 'SDI_R*.exe' -File -Recurse -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -notlike '*x64*' })
    }

    if ($sdiCandidates.Count -eq 0) {
        throw "SDI executable not found in $driversPath"
    }

    $sdiExe = $sdiCandidates |
        Sort-Object `
            @{ Expression = {
                $revision = $_.BaseName -replace '^SDI(?:_x64)?_R', ''
                $number = 0L
                if ([long]::TryParse($revision, [ref]$number)) {
                    $number
                }
                else {
                    0L
                }
            }; Descending = $true },
            LastWriteTime -Descending |
        Select-Object -First 1

    $sdiRoot = $sdiExe.DirectoryName
    $sdiDriversPath = Join-Path -Path $sdiRoot -ChildPath 'Drivers'
    $sdiIndexPath = Join-Path -Path $sdiRoot -ChildPath 'Index\SDI'
    $sdiOutputPath = Join-Path -Path $sdiIndexPath -ChildPath 'txt'
    $sdiToolsPath = Join-Path -Path $sdiRoot -ChildPath 'Tools\SDI'

    foreach ($directory in @($sdiDriversPath, $sdiIndexPath, $sdiOutputPath, $sdiToolsPath)) {
        if (-not (Test-Path -LiteralPath $directory -PathType Container)) {
            New-Item -ItemType Directory -Path $directory -Force -ErrorAction Stop | Out-Null
        }
    }

    $sdiConfigPath = Join-Path -Path $sdiRoot -ChildPath 'sdi.cfg'
    if (Test-Path -LiteralPath $sdiConfigPath -PathType Leaf) {
        $sdiConfigBackupPath = Join-Path -Path $logPath -ChildPath "sdi-$timestamp.cfg.bak"
        Copy-Item -LiteralPath $sdiConfigPath -Destination $sdiConfigBackupPath -Force -ErrorAction Stop

        $sdiConfig = Get-Content -LiteralPath $sdiConfigPath -Raw -ErrorAction Stop
        $updatedConfig = $sdiConfig -replace '(?i)(?<!\S)"?-checkupdates"?(?!\S)', ''
        if ($updatedConfig -ne $sdiConfig) {
            Set-Content -LiteralPath $sdiConfigPath -Value $updatedConfig -Encoding Default -Force -ErrorAction Stop
            Write-Host 'SDI online updates disabled for this run.' -ForegroundColor Gray
        }
    }

    $sdiArguments = @(
        '-autoinstall'
        '-nogui'
        '-autoclose'
        '-norestorepnt'
        ('-drp_dir:"{0}"' -f $sdiDriversPath)
        ('-index_dir:"{0}"' -f $sdiIndexPath)
        ('-output_dir:"{0}"' -f $sdiOutputPath)
        ('-data_dir:"{0}"' -f $sdiToolsPath)
        ('-log_dir:"{0}"' -f $logPath)
    )

    if ($RestartIfRequired) {
        $sdiArguments += '-finishrb_cmd:"shutdown -r -t 15"'
    }

    Write-Host "Starting SDI: $($sdiExe.FullName)" -ForegroundColor Cyan
    Write-Host "SDI logs: $logPath" -ForegroundColor Gray

    $process = Start-Process -FilePath $sdiExe.FullName -ArgumentList $sdiArguments -WorkingDirectory $sdiExe.DirectoryName -Wait -PassThru -NoNewWindow -ErrorAction Stop
    $exitCode = $process.ExitCode

    if ($exitCode -eq 0 -or $exitCode -eq 1) {
        Write-Host "SDI completed successfully. Exit code: $exitCode" -ForegroundColor Green
    }
    elseif ([uint32]$exitCode -eq 0x80000001) {
        Write-Host 'SDI completed; a restart may be required.' -ForegroundColor Yellow
    }
    else {
        Write-Host "SDI finished with exit code: $exitCode. Check the SDI logs." -ForegroundColor Red
    }

    exit $exitCode
}
catch {
    Write-Error "Driver update failed: $($_.Exception.Message)"
    exit 1
}
finally {
    if ($sdiConfigBackupPath -and (Test-Path -LiteralPath $sdiConfigBackupPath -PathType Leaf)) {
        try {
            Copy-Item -LiteralPath $sdiConfigBackupPath -Destination $sdiConfigPath -Force -ErrorAction Stop
            Remove-Item -LiteralPath $sdiConfigBackupPath -Force -ErrorAction SilentlyContinue
        }
        catch {
            Write-Warning "Failed to restore SDI configuration: $($_.Exception.Message)"
        }
    }

    if ($transcriptStarted) {
        Stop-Transcript | Out-Null
    }
}
