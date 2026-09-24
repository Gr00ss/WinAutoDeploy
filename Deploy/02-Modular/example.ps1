[CmdletBinding()]
param()

# =============================================
# example.ps1 — шаблон модуля раздела 02-Modular
# Скопируйте файл под новым именем и заполните логику
# =============================================

$ErrorActionPreference = 'Stop'

# Рабочие директории модуля. Все пути строятся от $PSScriptRoot,
# поэтому модуль работает с любого носителя независимо от буквы диска
$scriptPath = $PSScriptRoot
$tempPath = Join-Path -Path $PSScriptRoot -ChildPath 'Temp'
$logPath = 'C:\DeployLog.txt'

Write-Output "Module: $PSCommandPath"
Write-Output "Section dir: $scriptPath"
Write-Output "Resources dir: $tempPath"
Write-Output "Log: $logPath"

if (-not (Test-Path -LiteralPath $tempPath -PathType Container)) {
    Write-Warning "Resources directory not found: $tempPath"
}

# TODO: добавьте логику модуля