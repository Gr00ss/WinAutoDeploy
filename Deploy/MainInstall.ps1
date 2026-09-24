[CmdletBinding()]
param(
    [string]$Section,
    [string]$Module,
    [switch]$List,
    [switch]$All,
    [switch]$DryRun,
    [switch]$NonInteractive,
    [switch]$Help
)

$ErrorActionPreference = 'Stop'

function Initialize-ConsoleEncoding {
    if ($Host.Name -ne 'ConsoleHost') { return }

    try {
        & chcp.com 65001 > $null
        $utf8 = New-Object System.Text.UTF8Encoding($false)
        [Console]::InputEncoding = $utf8
        [Console]::OutputEncoding = $utf8
    }
    catch {
    }
}

Initialize-ConsoleEncoding

function Test-IsTempDirectory {
    param([string]$Name)
    if ([string]::IsNullOrWhiteSpace($Name)) { return $false }
    return $Name.Trim().Equals('Temp', [System.StringComparison]::OrdinalIgnoreCase)
}

function Get-DeployRoot {
    return $PSScriptRoot
}

function Get-VisibleDirectories {
    param([string]$RootPath)
    $result = @()
    foreach ($item in Get-ChildItem -LiteralPath $RootPath -Directory -ErrorAction SilentlyContinue) {
        if (-not (Test-IsTempDirectory -Name $item.Name)) {
            $result += $item
        }
    }
    return $result | Sort-Object Name
}

function Get-VisibleScripts {
    param([string]$RootPath)
    $result = @()
    foreach ($item in Get-ChildItem -LiteralPath $RootPath -File -ErrorAction SilentlyContinue) {
        if ($item.Extension -ieq '.ps1' -and $item.Name -ine 'MainInstall.ps1') {
            $result += $item
        }
    }
    return $result | Sort-Object Name
}

function Get-ChildNodeTree {
    param([string]$Path)

    $scripts = @()
    $directories = @()

    foreach ($item in Get-ChildItem -LiteralPath $Path -Force -ErrorAction SilentlyContinue) {
        if ($item.PSIsContainer) {
            if (Test-IsTempDirectory -Name $item.Name) { continue }
            $directories += [pscustomobject]@{
                Name = $item.Name
                Type = 'Directory'
                Path = $item.FullName
            }
            continue
        }

        if ($item.Extension -ieq '.ps1' -and $item.Name -ine 'MainInstall.ps1') {
            $scripts += [pscustomobject]@{
                Name = $item.BaseName
                Type = 'Script'
                Path = $item.FullName
            }
        }
    }

    $scripts = $scripts | Sort-Object Name
    $directories = $directories | Sort-Object Name

    return @($scripts) + @($directories)
}

function Show-Help {
    Write-Host "Win Auto Deploy" -ForegroundColor Cyan
    Write-Host "Usage:" -ForegroundColor Yellow
    Write-Host "  .\MainInstall.ps1" -ForegroundColor Gray
    Write-Host "  .\MainInstall.ps1 -List" -ForegroundColor Gray
    Write-Host "  .\MainInstall.ps1 -Section '01-Standard'" -ForegroundColor Gray
    Write-Host "  .\MainInstall.ps1 -All" -ForegroundColor Gray
    Write-Host "  .\MainInstall.ps1 -Help" -ForegroundColor Gray
}

function Show-Logo {
    $logo = @(
        ' ________ __         _______         __          _____               __              '
        '|  |  |  |__|.-----.|   _   |.--.--.|  |_.-----.|     \.-----.-----.|  |.-----.--.--.'
        '|  |  |  |  ||     ||       ||  |  ||   _|  _  ||  --  |  -__|  _  ||  ||  _  |  |  |'
        '|________|__||__|__||___|___||_____||____|_____||_____/|_____|   __||__||_____|___  |'
        '                                                             |__|             |_____|'
    )

    foreach ($line in $logo) {
        [Console]::ForegroundColor = [ConsoleColor]::Green
        [Console]::WriteLine($line)
        [Console]::ResetColor()
    }
}

function Invoke-SelectedModule {
    param(
        [string]$ScriptPath,
        [switch]$DryRun
    )

    if (-not (Test-Path -LiteralPath $ScriptPath -PathType Leaf)) {
        throw "Module not found: $ScriptPath"
    }

    $resolved = (Get-Item -LiteralPath $ScriptPath).FullName
    $root = Get-DeployRoot
    if (-not $resolved.StartsWith($root, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Selected module is outside the Deploy root: $resolved"
    }

    Write-Host "" 
    Write-Host "Launching module: $resolved" -ForegroundColor Cyan

    if ($DryRun) {
        Write-Host "Dry run: module execution skipped." -ForegroundColor Yellow
        return
    }

    & $resolved
}

function Show-InteractiveMenu {
    param([string]$RootPath)

    $currentPath = $RootPath

    while ($true) {
        Clear-Host
        $visible = @(Get-ChildNodeTree -Path $currentPath)

        Write-Host "" 
        Show-Logo
        Write-Host "Root: $RootPath" -ForegroundColor DarkGray
        Write-Host "Current: $currentPath" -ForegroundColor DarkGray
        Write-Host ""

        if ($visible.Count -eq 0) {
            if ($currentPath -ne $RootPath) {
                Write-Host "No entries available in this directory." -ForegroundColor Yellow
                Write-Host "Press Enter to go back..." -ForegroundColor Gray
                Read-Host | Out-Null
                $currentPath = Split-Path -Path $currentPath -Parent
                continue
            }
            Write-Host "No entries available in this directory." -ForegroundColor Yellow
            return
        }

        for ($i = 0; $i -lt $visible.Count; $i++) {
            $entry = $visible[$i]
            if ($entry.Type -eq 'Script') {
                Write-Host ("[" + ($i + 1) + "] " + $entry.Name) -ForegroundColor Green
            }
            else {
                Write-Host ("[" + ($i + 1) + "] " + $entry.Name + " /") -ForegroundColor Yellow
            }
        }

        if ($currentPath -ne $RootPath) {
            Write-Host "[B] Back" -ForegroundColor DarkGray
        }

        Write-Host "[Q] Quit" -ForegroundColor DarkRed
        Write-Host ""

        $choice = Read-Host "Select item"
        if ([string]::IsNullOrWhiteSpace($choice)) { continue }

        $normalized = $choice.Trim().ToUpperInvariant()
        if ($normalized -eq 'Q') { return }
        if ($normalized -eq 'B' -and $currentPath -ne $RootPath) {
            $currentPath = Split-Path -Path $currentPath -Parent
            continue
        }

        $index = 0
        if (-not [int]::TryParse($choice, [ref]$index)) {
            Write-Host "Invalid selection." -ForegroundColor Red
            continue
        }

        if ($index -lt 1 -or $index -gt $visible.Count) {
            Write-Host "Selection out of range." -ForegroundColor Red
            continue
        }

        $selected = $visible[$index - 1]

        if ($selected.Type -eq 'Directory') {
            $currentPath = $selected.Path
            continue
        }

        if ($selected.Type -eq 'Script') {
            $confirm = Read-Host "Run '$($selected.Name)'? [Y/N]"
            if ($confirm -and $confirm.Trim().ToUpperInvariant() -eq 'Y') {
                try {
                    Invoke-SelectedModule -ScriptPath $selected.Path -DryRun:$DryRun
                }
                catch {
                    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
                }
                Read-Host "Press Enter to continue" | Out-Null
            }
        }
    }
}

if ($Help) {
    Show-Help
    exit 0
}

$deployRoot = Get-DeployRoot
if (-not (Test-Path -LiteralPath $deployRoot -PathType Container)) {
    throw "Deploy root not found: $deployRoot"
}

if ($List) {
    Write-Host "Available sections:" -ForegroundColor Cyan
    foreach ($dir in (Get-VisibleDirectories -RootPath $deployRoot)) {
        Write-Host "  - $($dir.Name)" -ForegroundColor Yellow
    }
    exit 0
}

if ($Section) {
    $sectionPath = Join-Path -Path $deployRoot -ChildPath $Section
    if (-not (Test-Path -LiteralPath $sectionPath -PathType Container)) {
        throw "Section not found: $Section"
    }

    if ($Module) {
        $modulePath = Join-Path -Path $sectionPath -ChildPath ($Module + '.ps1')
        Invoke-SelectedModule -ScriptPath $modulePath -DryRun:$DryRun
        exit 0
    }

    $items = Get-ChildNodeTree -Path $sectionPath
    Write-Host "Section: $Section" -ForegroundColor Cyan
    if ($items.Count -eq 0) {
        Write-Host "No modules in this section." -ForegroundColor Yellow
    }
    else {
        foreach ($item in $items) {
            $suffix = ''
            if ($item.Type -eq 'Directory') { $suffix = ' /' }
            Write-Host ("  - " + $item.Name + $suffix) -ForegroundColor $(if ($item.Type -eq 'Directory') { 'Yellow' } else { 'Green' })
        }
    }
    exit 0
}

if ($All) {
    foreach ($section in (Get-VisibleDirectories -RootPath $deployRoot)) {
        foreach ($script in (Get-VisibleScripts -RootPath $section.FullName)) {
            Write-Host "Will run: $($script.FullName)" -ForegroundColor DarkGray
            if (-not $DryRun) {
                try {
                    & $script.FullName
                }
                catch {
                    Write-Host "Failed: $($script.FullName) - $($_.Exception.Message)" -ForegroundColor Red
                }
            }
        }
    }
    exit 0
}

if ($NonInteractive -and -not ($List -or $Section -or $All)) {
    Write-Host "NonInteractive mode requires a target argument." -ForegroundColor Red
    Show-Help
    exit 1
}

Show-InteractiveMenu -RootPath $deployRoot
