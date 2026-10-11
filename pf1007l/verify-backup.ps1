# Re-reads the frame's eMMC from the start up to the user-data partition and compares it with backups/emmc-full.img.
# Run from an Administrator PowerShell while U-Boot exposes the eMMC:
#   powershell -ExecutionPolicy Bypass -File <repo>\verify-backup.ps1
# If the disk drops, re-run with -Start <byte offset> from the last progress line.
param([long]$Start = 0, [long]$ExpectSize = 15758000128)
$ErrorActionPreference = 'Stop'

$ExpectName = 'Linux UMS disk 0'
# PF1007L eMMC as exposed by U-Boot; override with -ExpectSize for a different unit.
$End        = [long]4366336 * 512     # UDISK (/data) starts here; it is user data that a factory reset recreates
$Chunk      = 1MB
$Here       = Split-Path -Parent $MyInvocation.MyCommand.Path
$ImgPath    = Join-Path $Here 'backups\emmc-full.img'

$disk = @(Get-Disk | Where-Object { $_.FriendlyName -eq $ExpectName -and $_.Size -eq $ExpectSize -and $_.BusType -eq 'USB' })
if ($disk.Count -ne 1) { throw "Expected exactly one '$ExpectName' of $ExpectSize bytes; found $($disk.Count)." }
$n = $disk[0].Number

$dev = New-Object IO.FileStream("\\.\PhysicalDrive$n", [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite)
$img = [IO.File]::OpenRead($ImgPath)
$a = New-Object byte[] $Chunk
$b = New-Object byte[] $Chunk
$sha = [Security.Cryptography.SHA256]::Create()
$pos = $Start - ($Start % $Chunk)
try {
    $dev.Position = $pos; $img.Position = $pos
    while ($pos -lt $End) {
        $want = [int][math]::Min([long]$Chunk, [long]($End - $pos))
        $ga = 0; while ($ga -lt $want) { $r = $dev.Read($a, $ga, $want - $ga); if ($r -le 0) { throw "Short device read at $pos" }; $ga += $r }
        $gb = 0; while ($gb -lt $want) { $r = $img.Read($b, $gb, $want - $gb); if ($r -le 0) { throw "Short image read at $pos" }; $gb += $r }
        $ha = [BitConverter]::ToString($sha.ComputeHash($a, 0, $want))
        $hb = [BitConverter]::ToString($sha.ComputeHash($b, 0, $want))
        if ($ha -ne $hb) {
            for ($i = 0; $i -lt $want; $i++) {
                if ($a[$i] -ne $b[$i]) { throw ("MISMATCH at byte {0} (sector {1})" -f ($pos + $i), [math]::Floor(($pos + $i) / 512)) }
            }
        }
        $pos += $want
        if (($pos % 256MB) -eq 0) { Write-Host ("  verified {0:N2} / {1:N2} GB  (resume with -Start {2})" -f ($pos/1GB), ($End/1GB), $pos) }
    }
} finally { $dev.Close(); $img.Close() }
Write-Host ("OK: first {0:N2} GB of the eMMC (everything except /data) matches the backup byte for byte." -f ($End/1GB))
