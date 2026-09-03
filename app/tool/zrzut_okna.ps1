# Zrzut ekranu samego okna aplikacji na Windowsie (nie całego pulpitu).
#
# Ustawia oknu podany rozmiar, wysuwa je na wierzch i zapisuje jego prostokąt
# do pliku PNG. Służy do oglądania układu na szerokim oknie bez zgadywania.
#
# Uruchomienie:
#   powershell -ExecutionPolicy Bypass -File tool/zrzut_okna.ps1 -Plik ekran.png -Szerokosc 1400 -Wysokosc 900
param(
  [string]$Plik = "okno.png",
  [int]$Szerokosc = 1400,
  [int]$Wysokosc = 900,
  [string]$Proces = "chatt"
)

Add-Type -AssemblyName System.Drawing
Add-Type @'
using System;
using System.Runtime.InteropServices;
public class Okno {
  [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr h, IntPtr after, int x, int y, int cx, int cy, uint flags);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
}
'@

$proc = Get-Process -Name $Proces -ErrorAction SilentlyContinue
if (-not $proc -or $proc.MainWindowHandle -eq 0) {
  Write-Error "Brak okna procesu $Proces"
  exit 1
}
$h = $proc.MainWindowHandle

# SWP_NOZORDER = 0x4
[Okno]::SetWindowPos($h, [IntPtr]::Zero, 60, 60, $Szerokosc, $Wysokosc, 0x4) | Out-Null
[Okno]::SetForegroundWindow($h) | Out-Null
Start-Sleep -Milliseconds 1200

$r = New-Object Okno+RECT
[Okno]::GetWindowRect($h, [ref]$r) | Out-Null
$w = $r.Right - $r.Left
$hgt = $r.Bottom - $r.Top

$bmp = New-Object System.Drawing.Bitmap $w, $hgt
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.CopyFromScreen($r.Left, $r.Top, 0, 0, $bmp.Size)
$bmp.Save($Plik, [System.Drawing.Imaging.ImageFormat]::Png)
$g.Dispose()
$bmp.Dispose()
Write-Output "zapisano $Plik ($w x $hgt)"
