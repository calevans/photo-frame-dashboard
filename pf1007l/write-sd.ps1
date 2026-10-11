# Writes uboot/fel-sdboot.sunxi to a microSD card at the 8 KiB offset the A33 boot ROM reads.
# With that card in the frame, Reset parks the SoC in FEL (USB recovery) mode and keeps it there.
# Run from an Administrator PowerShell; get the disk number and exact size from Get-Disk first:
#   powershell -ExecutionPolicy Bypass -File <repo>\write-sd.ps1 -DiskNumber 3 -ExpectSize 31914983424
param(
    [Parameter(Mandatory)][int]$DiskNumber,
    [Parameter(Mandatory)][long]$ExpectSize
)
$ErrorActionPreference = 'Stop'

$Here      = Split-Path -Parent $MyInvocation.MyCommand.Path
$ImagePath = Join-Path $Here 'uboot\fel-sdboot.sunxi'
$ImageSha  = '19DB8994363B1464A1DE82E1C90AB63C5A985D1C96B57403D039D69BFFF39F14'
$Offset    = 8192

# Both numbers must match, so a typo cannot point this at a system disk.
$disk = Get-Disk -Number $DiskNumber
if ($disk.Size -ne $ExpectSize -or $disk.BusType -ne 'USB') {
    throw "Disk $DiskNumber is '$($disk.FriendlyName)' $($disk.Size) bytes $($disk.BusType); expected a USB disk of $ExpectSize bytes. Aborting."
}
if ((Get-FileHash $ImagePath -Algorithm SHA256).Hash -ne $ImageSha) { throw "fel-sdboot.sunxi hash mismatch" }

$img = [IO.File]::ReadAllBytes($ImagePath)
$part = Get-Partition -DiskNumber $DiskNumber -ErrorAction SilentlyContinue | Sort-Object Offset | Select-Object -First 1
if ($part -and ($Offset + $img.Length) -gt $part.Offset) { throw "Image would overlap the partition at $($part.Offset). Aborting." }

$BackupPath = Join-Path $Here "backups\sd-$ExpectSize-first-16MiB.bin"
$dev = New-Object IO.FileStream("\\.\PhysicalDrive$DiskNumber", [IO.FileMode]::Open, [IO.FileAccess]::ReadWrite, [IO.FileShare]::ReadWrite)
try {
    if (-not (Test-Path $BackupPath)) {
        $backup = New-Object byte[] (16MB)
        $dev.Position = 0
        $read = 0
        while ($read -lt $backup.Length) { $n = $dev.Read($backup, $read, $backup.Length - $read); if ($n -le 0) { break }; $read += $n }
        New-Item -ItemType Directory -Force -Path (Split-Path $BackupPath) | Out-Null
        [IO.File]::WriteAllBytes($BackupPath, $backup)
        Write-Host "Backed up the card's first 16 MiB to $BackupPath"
    }

    $dev.Position = $Offset
    $dev.Write($img, 0, $img.Length)
    $dev.Flush()

    $check = New-Object byte[] $img.Length
    $dev.Position = $Offset
    $read = 0
    while ($read -lt $check.Length) { $n = $dev.Read($check, $read, $check.Length - $read); if ($n -le 0) { break }; $read += $n }
} finally {
    $dev.Close()
}

$sha = [Security.Cryptography.SHA256]::Create()
if ([BitConverter]::ToString($sha.ComputeHash($img)) -ne [BitConverter]::ToString($sha.ComputeHash($check))) { throw "Readback mismatch" }
Write-Host "OK: fel-sdboot.sunxi written at offset $Offset and verified."
