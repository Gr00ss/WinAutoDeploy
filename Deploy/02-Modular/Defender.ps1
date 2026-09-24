[CmdletBinding()]
param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$Arguments
)

$scriptPath = Join-Path -Path $PSScriptRoot -ChildPath 'Temp\WindowsDefenderRemover\script\Script_Run.cmd'

if (-not (Test-Path -LiteralPath $scriptPath -PathType Leaf)) {
    throw "Defender remover script not found: $scriptPath"
}

$commandLine = '"{0}"' -f $scriptPath
if ($Arguments.Count -gt 0) {
    $commandLine += ' ' + ($Arguments -join ' ')
}

& $env:ComSpec /d /c $commandLine
exit $LASTEXITCODE
