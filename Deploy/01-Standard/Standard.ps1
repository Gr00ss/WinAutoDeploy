Start-Transcript -Path "C:\DeployLog.txt" -Force
Write-Output "=== START MAIN DEPLOY SCRIPT ==="

$scriptPath = $PSScriptRoot
$deployRoot = Split-Path -Path $scriptPath -Parent
Write-Output "Script launched from: $scriptPath"
Write-Output "Deploy root: $deployRoot"

$sectionTemp = Join-Path -Path $scriptPath -ChildPath "Temp"
$deployTemp = Join-Path -Path $deployRoot -ChildPath "Temp"

function Get-AppPath {
    param([string]$RelPath)
    foreach ($base in @($sectionTemp, $deployTemp)) {
        $candidate = Join-Path -Path $base -ChildPath $RelPath
        if (Test-Path -LiteralPath $candidate) { return $candidate }
    }
    return $null
}

# 1. ITERON
Write-Output "Copying iteron.exe..."
$iteronSrc = Get-AppPath "iteron.exe"
$desktopPath = "C:\Users\Public\Desktop"
$iteronDest = $desktopPath + "\iteron.exe"
Copy-Item -Path $iteronSrc -Destination $iteronDest -Force

Write-Output "Applying admin rights to iteron.exe..."
$appCompatPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\AppCompatFlags\Layers"
if (-not (Test-Path $appCompatPath)) { New-Item -Path $appCompatPath -Force | Out-Null }
Set-ItemProperty -Path $appCompatPath -Name $iteronDest -Value "~ RUNASADMIN" -Force

# 2. ANYDESK
$anyDesk = Get-AppPath "AnyDesk.exe"
if ($anyDesk) {
    Write-Output "Installing AnyDesk..."
    $adArgs = "--install `"C:\Program Files (x86)\AnyDesk`" --start-with-win --silent --create-shortcuts --create-desktop-icon"
    Start-Process -FilePath $anyDesk -ArgumentList $adArgs -Wait -NoNewWindow
}

# 3. CHROME
$chrome = Get-AppPath "ChromeSetup.exe"
if ($chrome) {
    Write-Output "Installing Google Chrome..."
    Start-Process -FilePath $chrome -ArgumentList "/silent /install" -Wait -NoNewWindow
}

# 4. 7-ZIP
$sevenZip = Get-AppPath "7z2602-x64.exe"
if ($sevenZip) {
    Write-Output "Installing 7-Zip..."
    Start-Process -FilePath $sevenZip -ArgumentList "/S" -Wait -NoNewWindow
}

# 5. PDFXCHANGE
$pdfInstall = Get-AppPath "PDFXChange\INSTALL.cmd"
if ($pdfInstall) {
    Write-Output "Installing PDFXChange..."
    $pdfDir = Split-Path -Path $pdfInstall -Parent
    Set-Location -Path $pdfDir
    Start-Process -FilePath "cmd.exe" -ArgumentList "/c INSTALL.cmd" -Wait
}

# 6. MS OFFICE
$imgPath = Get-AppPath "O365ProPlusRetail.img"
if ($imgPath) {
    Write-Output "Mounting Office image..."
    $mountResult = Mount-DiskImage -ImagePath $imgPath -PassThru
    $imgDrive = ($mountResult | Get-Volume).DriveLetter
    
    if ($imgDrive) {
        $setupPath = $imgDrive + ":\Setup.exe"
        $workDir = $imgDrive + ":\"
        
        if (Test-Path $setupPath) {
            Write-Output "Running Office setup..."
            Start-Process -FilePath $setupPath -WorkingDirectory $workDir -NoNewWindow
            Start-Sleep -Seconds 15 
            while (Get-Process -Name "Setup", "Setup32", "Setup64" -ErrorAction SilentlyContinue) { Start-Sleep -Seconds 5 }
        }
        Dismount-DiskImage -ImagePath $imgPath | Out-Null
    }
}

# 7. VC REDIST
Write-Output "Installing VC Redist via winget..."
$vcRedistIds = @(
    "Microsoft.VCRedist.2005.x86",
    "Microsoft.VCRedist.2005.x64",
    "Microsoft.VCRedist.2008.x86",
    "Microsoft.VCRedist.2008.x64",
    "Microsoft.VCRedist.2010.x86",
    "Microsoft.VCRedist.2010.x64",
    "Microsoft.VCRedist.2012.x86",
    "Microsoft.VCRedist.2012.x64",
    "Microsoft.VCRedist.2013.x86",
    "Microsoft.VCRedist.2013.x64",
    "Microsoft.VCRedist.2015+.x86",
    "Microsoft.VCRedist.2015+.x64"
)
foreach ($id in $vcRedistIds) {
    Write-Output "Installing $id..."
    winget install --id=$id -e --accept-source-agreements --accept-package-agreements
}

# 8. ACTIVATION
Write-Output "Checking internet connection..."
if (Test-Connection -ComputerName "77.88.8.8" -Count 1 -Quiet -ErrorAction SilentlyContinue) {
    Write-Host "Internet is UP. Activating..."
    & ([ScriptBlock]::Create((irm https://get.activated.win))) /Ohook /HWID
} else {
    Write-Host "No internet. Activation skipped."
}

Write-Output "=== END DEPLOY SCRIPT ==="
Stop-Transcript