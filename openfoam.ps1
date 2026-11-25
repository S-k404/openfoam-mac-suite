<#
.SYNOPSIS
    OpenFOAM Docker Runner & CLI for Windows 11.
.DESCRIPTION
    Cross-platform PowerShell equivalent of openfoam.sh: verifies/starts Docker
    Desktop, mounts the local workspace at /home/openfoam, launches native Windows
    ParaView for .foam cases, and opens the real-time web monitor.
#>
param(
    [Parameter(Position = 0)]
    [string]$Command = "shell",
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$Rest
)
$ErrorActionPreference = "Stop"
$WorkspaceRoot = $PSScriptRoot
$Image = "opencfd/openfoam-default:latest"
$ContainerBase = "/home/openfoam"

function Ensure-DockerRunning {
    try {
        docker info *> $null
        if ($LASTEXITCODE -eq 0) { return }
    } catch {}
    Write-Host "Docker is not running. Attempting to start Docker Desktop..." -ForegroundColor Yellow
    $dd = Join-Path $Env:ProgramFiles "Docker\Docker\Docker Desktop.exe"
    if (Test-Path $dd) { Start-Process -FilePath $dd }
    for ($i = 0; $i -lt 30; $i++) {
        Start-Sleep -Seconds 1
        try {
            docker info *> $null
            if ($LASTEXITCODE -eq 0) { return }
        } catch {}
    }
    throw "Docker daemon could not be reached after 30 seconds. Open Docker Desktop and retry."
}

function Find-ParaView {
    param([string]$ExeName = "paraview.exe")
    $cmd = Get-Command $ExeName -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    foreach ($root in @($Env:ProgramFiles, ${Env:ProgramFiles(x86)}, $Env:LOCALAPPDATA)) {
        if (-not $root) { continue }
        $hits = Get-ChildItem -Path $root -Filter "ParaView*" -Directory -ErrorAction SilentlyContinue | Sort-Object Name -Descending
        foreach ($h in $hits) {
            $cand = Join-Path $h.FullName "bin\$ExeName"
            if (Test-Path $cand) { return $cand }
        }
    }
    return $null
}

switch ($Command) {
    "doctor" {
        Ensure-DockerRunning
        Write-Host "Docker Desktop: OK" -ForegroundColor Green
        $pv = Find-ParaView "paraview.exe"
        if ($pv) { Write-Host "ParaView: $pv" -ForegroundColor Green } else { Write-Host "ParaView: not installed (winget install Kitware.ParaView)" -ForegroundColor Yellow }
        break
    }
    "live" {
        $py = if (Get-Command py -ErrorAction SilentlyContinue) { "py -3" } else { "python" }
        Invoke-Expression "$py `"$WorkspaceRoot\viewer\live_monitor.py`""
        break
    }
    "paraFoam" {
        $target = if ($Rest -and $Rest.Count -gt 0) { Resolve-Path $Rest[0] } else { Get-Location }
        $caseDir = if (Test-Path $target -PathType Leaf) { Split-Path $target -Parent } else { [string]$target }
        $caseName = Split-Path $caseDir -Leaf
        $foamFile = Join-Path $caseDir "$caseName.foam"
        if (-not (Test-Path $foamFile)) { New-Item -ItemType File -Path $foamFile -Force | Out-Null }
        $pv = Find-ParaView "paraview.exe"
        if (-not $pv) { throw "ParaView not found. Install via: winget install Kitware.ParaView" }
        Start-Process -FilePath $pv -ArgumentList "`"$foamFile`""
        break
    }
    default {
        Ensure-DockerRunning
        $mountSpec = "${WorkspaceRoot}:${ContainerBase}"
        if ($Command -eq "shell") {
            docker run --rm -it --ipc=host --shm-size=4g -v $mountSpec -w $ContainerBase $Image bash
        } else {
            $joined = (@($Command) + $Rest) -join " "
            docker run --rm -it --ipc=host --shm-size=4g -v $mountSpec -w $ContainerBase $Image bash -lc "source /usr/lib/openfoam/openfoam*/etc/bashrc 2>/dev/null || true; $joined"
        }
    }
}
