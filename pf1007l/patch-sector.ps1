# Writes the one-sector build.prop change that turns ADB on (persist.sys.usb.config=mass_storage -> adb).
# Run from an Administrator PowerShell while U-Boot exposes the eMMC:
#   powershell -ExecutionPolicy Bypass -File <repo>\patch-sector.ps1
# Undo (puts the stock sector back):
#   powershell -ExecutionPolicy Bypass -File <repo>\patch-sector.ps1 -Restore
param([switch]$Restore, [long]$ExpectSize = 15758000128)
$ErrorActionPreference = 'Stop'

$ExpectName = 'Linux UMS disk 0'
# PF1007L eMMC as exposed by U-Boot; override with -ExpectSize for a different unit.
$Here       = Split-Path -Parent $MyInvocation.MyCommand.Path
$Sector     = [long](Get-Content (Join-Path $Here 'patch\sector-number.txt'))
$Orig       = [IO.File]::ReadAllBytes((Join-Path $Here 'patch\sector-orig.bin'))
$Adb        = [IO.File]::ReadAllBytes((Join-Path $Here 'patch\sector-adb.bin'))
if ($Restore) { $From = $Adb; $To = $Orig; $What = 'stock' } else { $From = $Orig; $To = $Adb; $What = 'ADB-enabled' }

function Hash([byte[]]$b) { [BitConverter]::ToString([Security.Cryptography.SHA256]::Create().ComputeHash($b)).Replace('-', '') }

$disk = @(Get-Disk | Where-Object { $_.FriendlyName -eq $ExpectName -and $_.Size -eq $ExpectSize -and $_.BusType -eq 'USB' })
if ($disk.Count -ne 1) { throw "Expected exactly one '$ExpectName' of $ExpectSize bytes; found $($disk.Count)." }
$n = $disk[0].Number

function Read-Sector {
    $s = New-Object IO.FileStream("\\.\PhysicalDrive$n", [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite)
    try { $b = New-Object byte[] 512; $s.Position = $Sector * 512; [void]$s.Read($b, 0, 512); return ,$b } finally { $s.Close() }
}

$now = Read-Sector
$hNow = Hash $now
if ($hNow -eq (Hash $To)) { Write-Host "Sector $Sector already holds the $What version. Nothing to do."; exit 0 }
if ($hNow -ne (Hash $From)) { throw "Sector $Sector does not match the expected contents ($hNow). Refusing to write." }

Set-Disk -Number $n -IsReadOnly $false
try {
    $s = New-Object IO.FileStream("\\.\PhysicalDrive$n", [IO.FileMode]::Open, [IO.FileAccess]::ReadWrite, [IO.FileShare]::ReadWrite)
    try { $s.Position = $Sector * 512; $s.Write($To, 0, 512); $s.Flush() } finally { $s.Close() }
} finally {
    Set-Disk -Number $n -IsReadOnly $true
}

$back = Read-Sector
if ((Hash $back) -ne (Hash $To)) { throw "Readback mismatch after write. Run with -Restore, or restore from backups/emmc-full.img." }
Write-Host "OK: sector $Sector now holds the $What build.prop line, verified by readback. Disk re-marked read-only."
