[CmdletBinding()]
param()

$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator
)

if (-not $isAdmin) {
    Write-Host 'Requesting Administrator privileges...' -ForegroundColor Yellow
    $arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
    Start-Process -FilePath 'powershell.exe' -Verb RunAs -ArgumentList $arguments
    exit 0
}

$registryPath = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System'
$propertyName = 'EnableLUA'

try {
    if (Get-ItemProperty -Path $registryPath -Name $propertyName -ErrorAction SilentlyContinue) {
        Set-ItemProperty -Path $registryPath -Name $propertyName -Value 0 -ErrorAction Stop
    }
    else {
        New-ItemProperty -Path $registryPath -Name $propertyName -PropertyType DWord -Value 0 -Force -ErrorAction Stop | Out-Null
    }

    Write-Host 'UAC has been disabled.' -ForegroundColor Green
}
catch {
    Write-Error "Failed to disable UAC: $($_.Exception.Message)"
    exit 1
}
