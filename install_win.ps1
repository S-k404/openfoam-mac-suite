$ErrorActionPreference = "Stop"
Set-Location -LiteralPath $PSScriptRoot

$binDir = Join-Path $env:USERPROFILE ".local\bin"
New-Item -ItemType Directory -Force -Path $binDir | Out-Null

@"
@echo off
powershell -NoProfile -ExecutionPolicy Bypass -File "$PSScriptRoot\openfoam.ps1" %*
"@ | Set-Content -Path (Join-Path $binDir "openfoam.cmd") -Encoding Ascii

@"
@echo off
powershell -NoProfile -ExecutionPolicy Bypass -File "$PSScriptRoot\openfoam.ps1" paraFoam %*
"@ | Set-Content -Path (Join-Path $binDir "paraFoam.cmd") -Encoding Ascii

@"
@echo off
powershell -NoProfile -ExecutionPolicy Bypass -File "$PSScriptRoot\openfoam.ps1" live %*
"@ | Set-Content -Path (Join-Path $binDir "foam-live.cmd") -Encoding Ascii

$userPath = [Environment]::GetEnvironmentVariable("Path", "User")
if (-not $userPath -or ($userPath.Split(";") -notcontains $binDir)) {
    [Environment]::SetEnvironmentVariable("Path", $(if ($userPath) { "$binDir;$userPath" } else { $binDir }), "User")
    Write-Host "Added $binDir to User PATH." -ForegroundColor Cyan
}

Write-Host "OpenFOAM Windows wrappers installed in $binDir (openfoam.cmd, paraFoam.cmd, foam-live.cmd)." -ForegroundColor Green
