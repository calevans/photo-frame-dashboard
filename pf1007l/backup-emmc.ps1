# Full, verified, read-only image of the frame's eMMC while U-Boot exposes it over USB.
# Run from an Administrator PowerShell:
#   powershell -ExecutionPolicy Bypass -File <repo>\backup-emmc.ps1
param([long]$ExpectSize = 15758000128)
$ErrorActionPreference = 'Stop'

$ExpectName = 'Linux UMS disk 0'
# PF1007L eMMC as exposed by U-Boot; override with -ExpectSize for a different unit.
$Here       = Split-Path -Parent $MyInvocation.MyCommand.Path
$OutDir     = Join-Path $Here 'backups'
$OutPath    = Join-Path $OutDir 'emmc-full.img'
$Chunk      = 1MB

$disk = @(Get-Disk | Where-Object { $_.FriendlyName -eq $ExpectName -and $_.Size -eq $ExpectSize -and $_.BusType -eq 'USB' })
if ($disk.Count -ne 1) { throw "Expected exactly one '$ExpectName' of $ExpectSize bytes; found $($disk.Count). Is U-Boot's USB disk up?" }
$n = $disk[0].Number

# Block Windows from writing anything to the frame's storage while we read it.
# Changing the attribute makes Windows poke the device, which U-Boot's gadget may not survive, so only do it once.
if (-not $disk[0].IsReadOnly) {
    Set-Disk -Number $n -IsReadOnly $true
    Write-Host "Disk $n marked read-only"
} else {
    Write-Host "Disk $n already read-only"
}

function Read-Disk([string]$dest) {
    $sha = [Security.Cryptography.SHA256]::Create()
    $src = New-Object IO.FileStream("\\.\PhysicalDrive$n", [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite)
    $out = if ($dest) { [IO.File]::Create($dest) } else { $null }
    $buf = New-Object byte[] $Chunk
    $done = [long]0
    $sw = [Diagnostics.Stopwatch]::StartNew()
    try {
        while ($done -lt $ExpectSize) {
            $want = [int][math]::Min([long]$Chunk, [long]($ExpectSize - $done))
            $got = $src.Read($buf, 0, $want)
            if ($got -le 0) { throw "Short read at byte $done" }
            [void]$sha.TransformBlock($buf, 0, $got, $null, 0)
            if ($out) { $out.Write($buf, 0, $got) }
            $done += $got
            if (($done % 512MB) -lt $Chunk) {
                $mbs = [math]::Round($done / 1MB / [math]::Max($sw.Elapsed.TotalSeconds, 1), 1)
                Write-Host ("  {0:N1} / {1:N1} GB  ({2} MB/s)" -f ($done/1GB), ($ExpectSize/1GB), $mbs)
            }
        }
        [void]$sha.TransformFinalBlock($buf, 0, 0)
    } finally {
        $src.Close(); if ($out) { $out.Close() }
    }
    return [BitConverter]::ToString($sha.Hash).Replace('-', '')
}

New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
Write-Host "Pass 1: imaging to $OutPath"
$h1 = Read-Disk $OutPath
Write-Host "Pass 1 SHA-256: $h1"
Write-Host "Pass 2: re-reading the disk to verify"
$h2 = Read-Disk $null
Write-Host "Pass 2 SHA-256: $h2"
$len = (Get-Item $OutPath).Length
if ($h1 -ne $h2) { throw "Disk read is not stable: hashes differ between passes" }
if ($len -ne $ExpectSize) { throw "Image is $len bytes, expected $ExpectSize" }
"$h1  emmc-full.img" | Set-Content -Encoding ascii (Join-Path $OutDir 'emmc-full.img.sha256')
Write-Host "OK: $len bytes, SHA-256 $h1, verified by two independent reads."
