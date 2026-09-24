[CmdletBinding()]
param()
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
Write-Output "Checking internet connection..."
if (Test-Connection -ComputerName "1.1.1.1" -Count 1 -Quiet -ErrorAction SilentlyContinue) {
    Write-Host "Internet is UP. Activating..."
    & ([ScriptBlock]::Create((irm https://get.activated.win))) /HWID /Ohook
} else {
    Write-Host "No internet. Activation skipped."
}
